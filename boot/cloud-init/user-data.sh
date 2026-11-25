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
TAILSCALE_AUTH_KEY_PARAMETER="/mycomfy/tailscale-auth-key"
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

cat > /etc/apt/apt.conf.d/99mycomfy-disable-periodic-updates <<'APT_CONFIG'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT_CONFIG
for unit in apt-daily.timer apt-daily-upgrade.timer docker.socket docker.service containerd.service fwupd-refresh.timer; do
  if ! systemctl mask --now "$unit"; then
    printf '警告: %s を停止・無効化できませんでした。\n' "$unit" >&2
  fi
done

for apt_sources in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  if [ -f "$apt_sources" ]; then
    sed -i -E 's@http://(([^/[:space:]]+\.)?archive\.ubuntu\.com|security\.ubuntu\.com)/ubuntu@https://\1/ubuntu@g' "$apt_sources"
  fi
done

# aws cli が無ければ入れる（DLAMI には通常入っている）
if ! command -v aws >/dev/null || ! command -v unzip >/dev/null || ! command -v curl >/dev/null; then
  apt-get update --error-on=any
  apt-get install -y awscli unzip curl
fi

echo 'CloudWatch Agent の設定を開始します。'
touch /var/log/mycomfy/install.log /var/log/mycomfy/boot-check.log
if [ ! -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  (
    agent_download_dir=$(mktemp -d)
    trap 'rm -rf -- "$agent_download_dir"' EXIT
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 --max-time 120 \
      "https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/$(dpkg --print-architecture)/latest/amazon-cloudwatch-agent.deb" \
      --output "$agent_download_dir/amazon-cloudwatch-agent.deb"
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y \
      "$agent_download_dir/amazon-cloudwatch-agent.deb"
  )
fi
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c "ssm:${cloudwatch_agent_parameter}"
systemctl is-active --quiet amazon-cloudwatch-agent.service

aws s3 cp "s3://$BOOT_BUCKET/$BOOT_KEY" /tmp/mycomfy-boot.zip
unzip -o /tmp/mycomfy-boot.zip \
  -x scripts/notify-failure.sh systemd/mycomfy-notify-failure@.service \
  -d /opt/mycomfy/boot
chmod +x /opt/mycomfy/boot/install.sh

bash /opt/mycomfy/boot/install.sh
