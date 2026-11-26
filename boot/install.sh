#!/usr/bin/env bash
# mycomfy 初回セットアップ（user-data から呼ばれる）。
# やること：パッケージ導入 → Tailscale 参加 → マウント → ComfyUI 導入 →
# モデル取得（初回のみ）→ モデル同期 → ワークフロー配置 → systemd ユニット配置 → 起動と自己チェック。
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
apt-get install -y git curl unzip nfs-common jq

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

# --- モデル取得（初回のみ：S3 に無ければ取得元から取得して S3 へ保存する） ---
INSTALL_STAGE="モデル取得"
bash "$BOOT_DIR/scripts/download-models.sh"

# --- モデル同期（S3 → インスタンスストア） ---
INSTALL_STAGE="モデル同期"
bash "$BOOT_DIR/scripts/sync-models.sh"

# --- 台本生成プロンプトの取得（実値は SSM にだけ置く） ---
INSTALL_STAGE="台本生成プロンプトの取得"
if [ -n "${SCRIPT_GENERATION_PROMPT_PARAMETER:-}" ]; then
  aws ssm get-parameter --name "$SCRIPT_GENERATION_PROMPT_PARAMETER" --with-decryption \
    --query "Parameter.Value" --output text > /etc/mycomfy/script-generation-prompt.txt
  chmod 600 /etc/mycomfy/script-generation-prompt.txt
fi

# --- ワークフローの配置（API 形式は保管、UI 形式は ComfyUI のワークフロー置き場へ。台本生成プロンプトを注入する） ---
INSTALL_STAGE="ワークフローの配置"
bash "$BOOT_DIR/scripts/place-workflows.sh"

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
