#!/usr/bin/env bash
# mycomfy 初回セットアップ（user-data から呼ばれる）。
# やること：パッケージ導入 → Tailscale 参加 → マウント → ComfyUI 導入 →
# ワークフロー構築（S3 上のスクリプト一式）→ systemd ユニット配置 → 起動と自己チェック。
set -euo pipefail

BOOT_DIR="/opt/mycomfy/boot"
LOG="/var/log/mycomfy/install.log"
INSTALL_STAGE="初期設定"
finish_install() {
  if [ "$1" -ne 0 ] && [ ! -s /var/log/mycomfy/install-failure ]; then
    printf '%s\n' "$INSTALL_STAGE" > /var/log/mycomfy/install-failure
  fi
}
trap 'finish_install "$?"' EXIT
mkdir -p /var/log/mycomfy /etc/mycomfy
exec >> "$LOG" 2>&1
rm -f /var/log/mycomfy/install-failure /var/log/mycomfy/install-failure-hint /run/mycomfy-boot-status

echo "=== mycomfy install start: $(date -Is) ==="

# shellcheck disable=SC1091
. /etc/mycomfy/env

# --- パッケージ ---
INSTALL_STAGE="Ubuntu パッケージの導入"
export DEBIAN_FRONTEND=noninteractive
apt-get update --error-on=any
# ffmpeg は動画の結合（フレーム画像を動画ファイルへ束ねる処理）に使う
# attr は S3 Files の export 状態確認（getfattr）に使う
apt-get install -y git curl unzip nfs-common jq ffmpeg attr

# --- Tailscale（アクセス経路。後の工程が失敗しても SSH で入れるよう、早い段階で参加させる） ---
INSTALL_STAGE="Tailscale の導入"
bash "$BOOT_DIR/scripts/join-tailscale.sh" "$AWS_REGION" "$TAILSCALE_AUTH_KEY_PARAMETER"

INSTALL_STAGE="S3 Files クライアントの導入"
bash "$BOOT_DIR/scripts/install-s3files-client.sh"

# --- マウント ---
INSTALL_STAGE="インスタンスストアのマウント"
bash "$BOOT_DIR/scripts/mount-instance-store.sh"
INSTALL_STAGE="S3 Files のマウント"
bash "$BOOT_DIR/scripts/mount-s3files.sh"

# --- ComfyUI（版固定。DLAMI の PyTorch 環境を使う） ---
INSTALL_STAGE="ComfyUI の導入"
bash "$BOOT_DIR/scripts/install-comfyui.sh" "$COMFYUI_VERSION"

# --- ComfyUI バンドルの保存（1から構築した場合のみ。次回起動から使う。
# 中身は ComfyUI 本体＋venv のみ。カスタムノードは S3 側の担当で、
# リポジトリ側の仕組みは関知しない） ---
if [ -f /run/mycomfy-bundle-from-scratch ]; then
  INSTALL_STAGE="ComfyUI バンドルの保存"
  bash "$BOOT_DIR/scripts/capture-comfyui-bundle.sh"
fi

# --- ワークフロー構築（カスタムノード導入・モデル準備・ワークフロー配置は
# S3 上のスクリプト一式が担う。リポジトリ側は受け口だけを持つ） ---
INSTALL_STAGE="ワークフロー構築"
bash "$BOOT_DIR/scripts/run-workflow-setup.sh"

# --- systemd ユニット配置 ---
INSTALL_STAGE="systemd サービスの登録"
cp "$BOOT_DIR/systemd/comfyui.service" /etc/systemd/system/
systemctl daemon-reload

# --- 起動 ---
INSTALL_STAGE="ComfyUI の起動"
systemctl start comfyui.service
INSTALL_STAGE="起動時の自己チェック"
bash "$BOOT_DIR/scripts/self-check.sh"

echo "=== mycomfy install done: $(date -Is) ==="
