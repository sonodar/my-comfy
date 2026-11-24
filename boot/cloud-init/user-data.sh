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
TAILSCALE_AUTH_KEY_PARAMETER="${tailscale_auth_key_parameter}"
PROJECT_NAME="${project_name}"
INSTANCE_STORE_PATH="/mnt/instance-store"
S3FILES_MOUNT="/mnt/s3files"
ENVEOF
chmod 600 /etc/mycomfy/env
cp /etc/mycomfy/env /etc/mycomfy/notify.env

export AWS_DEFAULT_REGION="$AWS_REGION"

cat > /opt/mycomfy/boot/scripts/notify-failure.sh <<'NOTIFY_SCRIPT'
${notify_failure_script}
NOTIFY_SCRIPT
notify_user_data_failure() {
  local exit_status="$1" line="$2"
  local detail="user-data の $line 行目で失敗しました。終了コード $exit_status"
  if [ -s /var/log/mycomfy/install-failure ]; then
    detail="失敗した工程: $(cat /var/log/mycomfy/install-failure)。ログ: /var/log/mycomfy/install.log。終了コード $exit_status"
  fi
  if [ -s /var/log/mycomfy/install-failure-hint ]; then
    detail="$detail
対処: $(cat /var/log/mycomfy/install-failure-hint)"
  fi
  bash /opt/mycomfy/boot/scripts/notify-failure.sh 初回セットアップ "$detail" || true
}
trap 'notify_user_data_failure "$?" "$LINENO"' ERR
rm -f /var/log/mycomfy/install-failure /var/log/mycomfy/install-failure-hint

cat > /etc/systemd/system/mycomfy-notify-failure@.service <<'NOTIFY_UNIT'
${notify_failure_unit}
NOTIFY_UNIT

for apt_sources in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  if [ -f "$apt_sources" ]; then
    sed -i -E 's@http://(([^/[:space:]]+\.)?archive\.ubuntu\.com|security\.ubuntu\.com)/ubuntu@https://\1/ubuntu@g' "$apt_sources"
  fi
done

# aws cli が無ければ入れる（DLAMI には通常入っている）
if ! command -v aws >/dev/null 2>&1; then
  apt-get update --error-on=any
  apt-get install -y awscli unzip curl
fi

aws s3 cp "s3://$BOOT_BUCKET/$BOOT_KEY" /tmp/mycomfy-boot.zip
unzip -o /tmp/mycomfy-boot.zip \
  -x scripts/notify-failure.sh systemd/mycomfy-notify-failure@.service \
  -d /opt/mycomfy/boot
chmod +x /opt/mycomfy/boot/install.sh

bash /opt/mycomfy/boot/install.sh
