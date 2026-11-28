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
# tar も mv も実行中無言なので、アーカイブと移動のそれぞれで開始と完了を
# ログに残す（開始だけあって完了が無ければ、その工程で止まっていると
# 分かるようにする）。
echo "ComfyUI bundle archive start: $WORK ($(date -Is))"
tar -czf "$WORK" -C "$STORE_PATH" \
  --exclude="ComfyUI/output" \
  --exclude="ComfyUI/temp" \
  --exclude="*/__pycache__" \
  ComfyUI
echo "ComfyUI bundle archived: $WORK ($(du -h "$WORK" | cut -f1), $(date -Is))"
mv "$WORK" "$DEST"
echo "ComfyUI bundle moved: $DEST ($(date -Is))"
