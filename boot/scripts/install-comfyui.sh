#!/usr/bin/env bash
# ComfyUI の導入。バンドル（ComfyUI 本体＋カスタムノード＋venv を固めた tar）が
# S3 にあれば取得して展開し、なければ版を固定して clone＋venv 構築から行う。
# どちらの場合も最後に requirements への pip install を必ず実行し、差分だけを
# 補完する（満たされているものは pip が飛ばす）。
# 1から構築した場合は印を残す。カスタムノードまで入った状態で、install.sh が
# ワークフロー構築の後にバンドルとして S3 へ保存する。
set -euo pipefail

COMFYUI_VERSION="$1"

# shellcheck disable=SC1091
. /etc/mycomfy/env

BASE_PY="/opt/pytorch/bin/python"
VENV_PY="/opt/ComfyUI/venv/bin/python"
export AWS_DEFAULT_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"

if [ ! -x "$BASE_PY" ]; then
  echo "FATAL: $BASE_PY not found (DLAMI の PyTorch 環境が無い)" >&2
  exit 1
fi

if [ ! -d /opt/ComfyUI ]; then
  if aws s3api head-object --bucket "$COMFYUI_BUNDLE_BUCKET" --key "$COMFYUI_BUNDLE_KEY" >/dev/null 2>&1; then
    echo "ComfyUI bundle: s3://$COMFYUI_BUNDLE_BUCKET/$COMFYUI_BUNDLE_KEY を取得して展開する"
    aws s3 cp "s3://$COMFYUI_BUNDLE_BUCKET/$COMFYUI_BUNDLE_KEY" /tmp/comfyui-bundle.tar.gz >/dev/null
    tar --no-same-owner -xzf /tmp/comfyui-bundle.tar.gz -C /opt
    rm -f /tmp/comfyui-bundle.tar.gz
  else
    echo "ComfyUI bundle が無いため1から構築する (version: $COMFYUI_VERSION)"
    git clone --depth 1 --branch "$COMFYUI_VERSION" \
      https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI
    "$BASE_PY" -m venv /opt/ComfyUI/venv
    touch /run/mycomfy-bundle-from-scratch
  fi
fi
echo "ComfyUI commit: $(git -C /opt/ComfyUI rev-parse HEAD)"

# 差分の補完（毎起動ごとに必ず実行する）
"$VENV_PY" -m pip install -r /opt/ComfyUI/requirements.txt
