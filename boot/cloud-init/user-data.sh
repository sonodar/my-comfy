#!/bin/bash
# mycomfy user-data（初回起動時のみ実行される）。
# 実処理は S3 に置いた boot/ バンドル内の install.sh が担う。ここは小さく保つ。
# Terraform の templatefile で値を埋め込むため、このファイル内のドル波括弧は
# すべて Terraform 変数として扱われる。シェル側ではドル波括弧構文を使わないこと。
set -euo pipefail

exec > >(tee -a /var/log/mycomfy-user-data.log) 2>&1

BOOT_BUCKET="${boot_bucket}"
BOOT_KEY="${boot_key}"
AWS_REGION="${aws_region}"

mkdir -p /var/log/mycomfy /opt/mycomfy/boot/scripts /etc/mycomfy

# 個人値を env ファイルに落とす（install.sh と各スクリプトが読む）
cat > /etc/mycomfy/env <<'ENVEOF'
NOTIFY_TOPIC_ARN="${notify_topic_arn}"
S3_FILES_ID="${s3_files_id}"
AWS_REGION="${aws_region}"
COMFYUI_VERSION="${comfyui_version}"
BUCKET_NAME="${bucket_name}"
INSTANCE_STORE_PATH="/mnt/instance-store"
S3FILES_MOUNT="/mnt/s3files"
ENVEOF
chmod 600 /etc/mycomfy/env
cp /etc/mycomfy/env /etc/mycomfy/notify.env

export AWS_DEFAULT_REGION="$AWS_REGION"

cat > /opt/mycomfy/boot/scripts/notify-failure.sh <<'NOTIFY_SCRIPT'
${notify_failure_script}
NOTIFY_SCRIPT
trap 'bash /opt/mycomfy/boot/scripts/notify-failure.sh cloud-init-user-data "line=$LINENO exit=$?" || true' ERR

cat > /etc/systemd/system/mycomfy-notify-failure@.service <<'NOTIFY_UNIT'
${notify_failure_unit}
NOTIFY_UNIT

# aws cli が無ければ入れる（DLAMI には通常入っている）
if ! command -v aws >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y awscli unzip curl
fi

aws s3 cp "s3://$BOOT_BUCKET/$BOOT_KEY" /tmp/mycomfy-boot.zip
unzip -o /tmp/mycomfy-boot.zip \
  -x scripts/notify-failure.sh systemd/mycomfy-notify-failure@.service \
  -d /opt/mycomfy/boot
chmod +x /opt/mycomfy/boot/install.sh

bash /opt/mycomfy/boot/install.sh
