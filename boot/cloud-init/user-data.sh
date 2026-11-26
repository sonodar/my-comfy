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

mkdir -p /var/log/mycomfy /opt/mycomfy/boot/scripts /etc/mycomfy /usr/local/bin

# 個人値を env ファイルに落とす（install.sh と各スクリプトが読む）
cat > /etc/mycomfy/env <<'ENVEOF'
NOTIFY_TOPIC_ARN="${notify_topic_arn}"
S3_FILES_ID="${s3_files_id}"
AWS_REGION="${aws_region}"
COMFYUI_VERSION="${comfyui_version}"
BUCKET_NAME="${bucket_name}"
TAILSCALE_AUTH_KEY_PARAMETER="${tailscale_auth_key_parameter}"
MODEL_MANIFEST_PARAMETER="${model_manifest_parameter}"
SCRIPT_GENERATION_PROMPT_PARAMETER="${script_generation_prompt_parameter}"
INSTANCE_STORE_PATH="/mnt/instance-store"
S3FILES_MOUNT="/mnt/s3files"
ENVEOF
chmod 600 /etc/mycomfy/env

export AWS_DEFAULT_REGION="$AWS_REGION"
USER_DATA_STAGE=""

cat > /usr/local/bin/notify.sh <<'NOTIFY_COMMON_SCRIPT'
${notify_script}
NOTIFY_COMMON_SCRIPT
chmod 755 /usr/local/bin/notify.sh
notify_user_data_failure() {
  local exit_status="$1" line="$2"
  if grep -qx 'failure-notified' /run/mycomfy-boot-status 2>/dev/null; then
    return
  fi
  local detail="user-data の $line 行目で失敗しました。終了コード $exit_status"
  if [ -n "$USER_DATA_STAGE" ]; then
    printf -v detail '失敗した工程: %s。ログ: /var/log/mycomfy-user-data.log。%s' "$USER_DATA_STAGE" "$detail"
  fi
  if [ -s /var/log/mycomfy/install-failure ]; then
    detail="失敗した工程: $(cat /var/log/mycomfy/install-failure)。ログ: /var/log/mycomfy/install.log。終了コード $exit_status"
  fi
  if [ -s /var/log/mycomfy/install-failure-hint ]; then
    detail="$detail
対処: $(cat /var/log/mycomfy/install-failure-hint)"
  fi
  NOTIFY_TOPIC_ARN="${notify_topic_arn}" /usr/local/bin/notify.sh "mycomfy の起動処理に失敗しました。
対象: 初回セットアップ
ホスト: $(hostname)
時刻: $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %Z')
$detail" || true
}
rm -f /run/mycomfy-boot-status
trap 'notify_user_data_failure "$?" "$LINENO"' ERR
rm -f /var/log/mycomfy/install-failure /var/log/mycomfy/install-failure-hint

USER_DATA_STAGE="起動に必要なパッケージの準備"
bash -s <<'PREPARE_BOOT_DEPENDENCIES'
${prepare_boot_dependencies_script}
PREPARE_BOOT_DEPENDENCIES

USER_DATA_STAGE="不要サービスの停止"
bash -s <<'STOP_UNUSED_SERVICES'
${stop_unused_services_script}
STOP_UNUSED_SERVICES

USER_DATA_STAGE="CloudWatch Agent の設定と起動"
bash -s -- "${cloudwatch_agent_parameter}" <<'START_CLOUDWATCH_AGENT'
${start_cloudwatch_agent_script}
START_CLOUDWATCH_AGENT
USER_DATA_STAGE="起動用 ZIP の取得"
aws s3 cp "s3://$BOOT_BUCKET/$BOOT_KEY" /tmp/mycomfy-boot.zip
USER_DATA_STAGE="起動用 ZIP の展開"
unzip -o /tmp/mycomfy-boot.zip -d /opt/mycomfy/boot
chmod +x /opt/mycomfy/boot/install.sh

USER_DATA_STAGE="初回セットアップ"
bash /opt/mycomfy/boot/install.sh
