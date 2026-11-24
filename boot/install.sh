#!/usr/bin/env bash
# mycomfy 初回セットアップ（user-data から呼ばれる）。
# やること：パッケージ導入 → マウント → ComfyUI 導入 → systemd ユニット配置 → 起動。
# モデル同期はこのマイルストーンの範囲外。ComfyUI は空で起動するところまで。
set -euo pipefail

BOOT_DIR="/opt/mycomfy/boot"
LOG="/var/log/mycomfy/install.log"
INSTALL_STAGE="初期設定"
record_install_failure() {
  if [ "$1" -ne 0 ]; then
    printf '%s\n' "$INSTALL_STAGE" > /var/log/mycomfy/install-failure
  fi
}
# 失敗通知に「対処」を併記したい工程用。user-data 側の通知組み立てが拾う
write_install_failure_hint() {
  printf '%s\n' "$1" > /var/log/mycomfy/install-failure-hint
}
trap 'record_install_failure "$?"' EXIT
mkdir -p /var/log/mycomfy /etc/mycomfy
exec >> "$LOG" 2>&1

echo "=== mycomfy install start: $(date -Is) ==="

# shellcheck disable=SC1091
. /etc/mycomfy/env

# --- パッケージ ---
INSTALL_STAGE="Ubuntu パッケージの導入"
export DEBIAN_FRONTEND=noninteractive
apt-get update --error-on=any
apt-get install -y git curl unzip nfs-common

# --- Tailscale（アクセス経路。後の工程が失敗しても SSH で入れるよう、早い段階で参加させる） ---
INSTALL_STAGE="Tailscale の導入"
. /etc/os-release
TAILSCALE_KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" \
  -o "$TAILSCALE_KEYRING"
chmod a+r "$TAILSCALE_KEYRING"
printf 'deb [signed-by=%s] https://pkgs.tailscale.com/stable/ubuntu %s main\n' \
  "$TAILSCALE_KEYRING" "$VERSION_CODENAME" \
  > /etc/apt/sources.list.d/tailscale.list
apt-get update --error-on=any
apt-get install -y tailscale
systemctl enable --now tailscaled
# 認証キーは SSM パラメータストア（SecureString）から実行時に取得する。
# user-data や tfstate にキーを残さないための形。登録後はマシン自身の鍵で接続する。
# この構成ではインスタンスを作り直すたびに登録が走る。キーの期限（既定90日）が切れていると
# 登録が失敗する（工程名つきで通知される）。その場合は新しいキーを発行してパラメータの値を差し替える
INSTALL_STAGE="Tailscale 認証キーの取得"
if ! TAILSCALE_AUTH_KEY="$(aws ssm get-parameter \
  --name "$TAILSCALE_AUTH_KEY_PARAMETER" --with-decryption \
  --query Parameter.Value --output text --region "$AWS_REGION")"; then
  write_install_failure_hint "SSM パラメータ $TAILSCALE_AUTH_KEY_PARAMETER が存在しないか、読み取れませんでした。パラメータを作成済みか確認してください"
  exit 1
fi
INSTALL_STAGE="Tailscale の参加登録"
if ! tailscale up --auth-key "$TAILSCALE_AUTH_KEY" --hostname "$PROJECT_NAME" --timeout 120s; then
  write_install_failure_hint "認証キーの期限切れ・無効の可能性があります。新しいキー（Reusable + Ephemeral）を発行し、SSM パラメータ $TAILSCALE_AUTH_KEY_PARAMETER の値を差し替えてから、インスタンスを作り直してください"
  exit 1
fi
unset TAILSCALE_AUTH_KEY

INSTALL_STAGE="S3 Files クライアントの導入"
. /etc/os-release
EFS_UTILS_REPO="https://amazon-efs-utils.aws.com"
EFS_UTILS_KEYRING="/usr/share/keyrings/efs-utils.gpg"
curl -fsSL "$EFS_UTILS_REPO/efs-utils.gpg" -o "$EFS_UTILS_KEYRING"
chmod a+r "$EFS_UTILS_KEYRING"
printf 'deb [signed-by=%s] %s/repo/deb/%s/%s %s main\n' \
  "$EFS_UTILS_KEYRING" "$EFS_UTILS_REPO" "$ID" "$VERSION_ID" "$VERSION_ID" \
  > /etc/apt/sources.list.d/efs-utils.list
apt-get update --error-on=any
# amazon-efs-utils は mount -t s3files のヘルパを提供する（Ubuntu 24.04 の apt にある前提）
apt-get install -y amazon-efs-utils

# --- マウント ---
INSTALL_STAGE="インスタンスストアのマウント"
bash "$BOOT_DIR/scripts/mount-instance-store.sh"
INSTALL_STAGE="S3 Files のマウント"
bash "$BOOT_DIR/scripts/mount-s3files.sh"

# --- ComfyUI（版固定。DLAMI の PyTorch 環境を使う） ---
INSTALL_STAGE="ComfyUI の導入"
PY="/opt/pytorch/bin/python"
if [ ! -x "$PY" ]; then
  echo "FATAL: $PY not found (DLAMI の PyTorch 環境が無い)" >&2
  exit 1
fi

if [ ! -d /opt/ComfyUI ]; then
  git clone --depth 1 --branch "$COMFYUI_VERSION" \
    https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
fi
echo "ComfyUI commit: $(git -C /opt/ComfyUI rev-parse HEAD)"

"$PY" -m pip install -r /opt/ComfyUI/requirements.txt

# --- systemd ユニット配置 ---
INSTALL_STAGE="systemd サービスの登録"
cp "$BOOT_DIR/systemd/"*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable mycomfy-init.service comfyui.service mycomfy-self-check.service

# --- 起動 ---
INSTALL_STAGE="ストレージをマウントするサービスの起動"
systemctl start mycomfy-init.service
INSTALL_STAGE="ComfyUI の起動"
systemctl start comfyui.service
INSTALL_STAGE="起動時の自己チェック"
systemctl start mycomfy-self-check.service

echo "=== mycomfy install done: $(date -Is) ==="
