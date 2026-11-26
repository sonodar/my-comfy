#!/usr/bin/env bash
# 1から構築した ComfyUI 一式（本体＋カスタムノード＋venv）を tar に固めて
# S3 へ保存する。次回起動からはこのバンドルが使われる。
# カスタムノードの導入（ワークフロー構築）が終わった後に呼ぶこと。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env
export AWS_DEFAULT_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"

TMP="/tmp/comfyui-bundle.tar.gz"
tar -czf "$TMP" -C /opt \
  --exclude="ComfyUI/output" \
  --exclude="ComfyUI/temp" \
  --exclude="*/__pycache__" \
  ComfyUI
aws s3 cp "$TMP" "s3://$COMFYUI_BUNDLE_BUCKET/$COMFYUI_BUNDLE_KEY" >/dev/null
rm -f "$TMP"
echo "ComfyUI bundle saved: s3://$COMFYUI_BUNDLE_BUCKET/$COMFYUI_BUNDLE_KEY"
