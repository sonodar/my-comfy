#!/usr/bin/env bash
# 1から構築した ComfyUI（本体＋venv）を tar に固めて S3 Files へ出す。
# 次回起動からはこのバンドルが使われる。
# ComfyUI 導入の直後、カスタムノード導入の前に呼ぶこと。中身は本体と
# venv のみで、カスタムノードやモデルは含めない（どちらも S3 側の担当で、
# 起動のたびにツリーへ入れられる）。
# tar はインスタンスストア側で完成させてからマウントへ mv する。
# マウント上での長時間の書き込み中状態を作らないため。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
DEST="${S3FILES_MOUNT:-/mnt/s3files}/$COMFYUI_BUNDLE_KEY"
mkdir -p "$(dirname "$DEST")"
WORK="$STORE_PATH/$(basename "$DEST")"
# tar は実行中無言なので、開始と完了をログに残す（開始だけあって完了が
# 無ければ、この工程で止まっていると分かるようにする）。
echo "ComfyUI bundle save start: $DEST ($(date -Is))"
tar -czf "$WORK" -C "$STORE_PATH" \
  --exclude="ComfyUI/output" \
  --exclude="ComfyUI/temp" \
  --exclude="*/__pycache__" \
  ComfyUI
mv "$WORK" "$DEST"
echo "ComfyUI bundle saved: $DEST ($(du -h "$DEST" | cut -f1), $(date -Is))"
