#!/usr/bin/env bash
# mycomfy 初回セットアップ（user-data から呼ばれる）。
# やること：パッケージ導入 → マウント → ComfyUI 導入 → systemd ユニット配置 → 起動。
# モデル同期はこのマイルストーンの範囲外。ComfyUI は空で起動するところまで。
set -euo pipefail

BOOT_DIR="/opt/mycomfy/boot"
LOG="/var/log/mycomfy/install.log"
mkdir -p /var/log/mycomfy /etc/mycomfy
exec >> "$LOG" 2>&1

echo "=== mycomfy install start: $(date -Is) ==="

# shellcheck disable=SC1091
. /etc/mycomfy/env

# --- パッケージ ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# amazon-efs-utils は mount -t s3files のヘルパを提供する（Ubuntu 24.04 の apt にある前提）
apt-get install -y git curl unzip nfs-common amazon-efs-utils

# --- マウント ---
bash "$BOOT_DIR/scripts/mount-instance-store.sh"
bash "$BOOT_DIR/scripts/mount-s3files.sh"

# --- ComfyUI（版固定。DLAMI の PyTorch 環境を使う） ---
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
cp "$BOOT_DIR/systemd/"*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable mycomfy-init.service comfyui.service mycomfy-self-check.service

# --- 起動 ---
systemctl start mycomfy-init.service
systemctl start comfyui.service
systemctl start mycomfy-self-check.service

echo "=== mycomfy install done: $(date -Is) ==="
