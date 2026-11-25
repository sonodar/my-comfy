#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="$1"
TAILSCALE_AUTH_KEY_PARAMETER="$2"
TAILSCALE_AUTH_KEY_FILE=""
finish_tailscale_join() {
  if [ -n "$TAILSCALE_AUTH_KEY_FILE" ] && ! rm -f -- "$TAILSCALE_AUTH_KEY_FILE"; then
    printf '%s\n' 'Failed to remove the temporary Tailscale auth key file' >&2
  fi
  if [ "$1" -ne 0 ]; then
    printf '%s\n' "$INSTALL_STAGE" > /var/log/mycomfy/install-failure
  fi
}
# 失敗通知に「対処」を併記したい工程用。user-data 側の通知組み立てが拾う
write_install_failure_hint() {
  printf '%s\n' "$1" > /var/log/mycomfy/install-failure-hint
}
trap 'finish_tailscale_join "$?"' EXIT

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
TAILSCALE_AUTH_KEY_FILE="$(mktemp /run/mycomfy-tailscale-auth.XXXXXX)"
if ! aws ssm get-parameter \
  --name "$TAILSCALE_AUTH_KEY_PARAMETER" --with-decryption \
  --query Parameter.Value --output text --region "$AWS_REGION" > "$TAILSCALE_AUTH_KEY_FILE"; then
  write_install_failure_hint "SSM パラメータ $TAILSCALE_AUTH_KEY_PARAMETER が存在しないか、読み取れませんでした。パラメータを作成済みか確認してください"
  exit 1
fi
INSTALL_STAGE="Tailscale の参加登録"
if ! tailscale up --auth-key "file:$TAILSCALE_AUTH_KEY_FILE" --hostname mycomfy --timeout 120s; then
  write_install_failure_hint "認証キーの期限切れ・無効の可能性があります。新しいキー（Reusable + Ephemeral）を発行し、SSM パラメータ $TAILSCALE_AUTH_KEY_PARAMETER の値を差し替えてから、インスタンスを作り直してください"
  exit 1
fi
rm -f -- "$TAILSCALE_AUTH_KEY_FILE"
TAILSCALE_AUTH_KEY_FILE=""
