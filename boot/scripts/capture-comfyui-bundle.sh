#!/usr/bin/env bash
# 1から構築した ComfyUI（本体＋venv）を tar に固めて S3 Files へ直接
# 書き出す。次回起動からはこのバンドルが使われる。
# ComfyUI 導入の直後、カスタムノード導入の前に呼ぶこと。中身は本体と
# venv のみで、カスタムノードやモデルは含めない（どちらも S3 側の担当で、
# 起動のたびにツリーへ入れられる）。
# 書き込み途中の tar がバンドルとして読まれないよう、一時名で書いてから
# rename で確定させる。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
DEST="${S3FILES_MOUNT:-/mnt/s3files}/$COMFYUI_BUNDLE_KEY"
mkdir -p "$(dirname "$DEST")"
TMP="$DEST.tmp"
tar -czf "$TMP" -C "$STORE_PATH" \
  --exclude="ComfyUI/output" \
  --exclude="ComfyUI/temp" \
  --exclude="*/__pycache__" \
  ComfyUI
mv "$TMP" "$DEST"
echo "ComfyUI bundle saved: $DEST"
