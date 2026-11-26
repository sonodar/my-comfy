#!/usr/bin/env bash
# ComfyUI の導入。バンドル（ComfyUI 本体＋venv を固めた tar）が S3 Files
# 上にあれば直接展開し、なければ版を固定して clone＋venv 構築から行う。
# どちらの場合も最後に requirements への pip install を必ず実行し、差分だけを
# 補完する（満たされているものは pip が飛ばす）。
# 1から構築した場合は印を残し、install.sh がこの直後（ワークフロー構築の
# 前）にバンドルとして S3 Files へ保存する。カスタムノードはバンドルに
# 含めず、起動のたびに S3 側のスクリプトが入れる。
#
# 置き場はインスタンスストア（ルート EBS には置かない。CUDA 版 PyTorch
# 一式でルートが溢れるため）。参照する側もすべてインスタンスストア上の
# パスを直接使う（リンクは挟まない）。
set -euo pipefail

COMFYUI_VERSION="$1"

# shellcheck disable=SC1091
. /etc/mycomfy/env

BASE_PY="/opt/pytorch/bin/python"
STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
COMFYUI_DIR="$STORE_PATH/ComfyUI"
VENV_PY="$COMFYUI_DIR/venv/bin/python"
WORK_TMP="$STORE_PATH/tmp"
# pip の一時ファイルもインスタンスストアへ（ルートを圧迫しない）
export TMPDIR="$WORK_TMP"

if [ ! -x "$BASE_PY" ]; then
  echo "FATAL: $BASE_PY not found (DLAMI の PyTorch 環境が無い)" >&2
  exit 1
fi
mkdir -p "$WORK_TMP"

BUNDLE_PATH="${S3FILES_MOUNT:-/mnt/s3files}/$COMFYUI_BUNDLE_KEY"
if [ ! -d "$COMFYUI_DIR" ]; then
  if [ -f "$BUNDLE_PATH" ]; then
    echo "ComfyUI bundle: $BUNDLE_PATH を展開する"
    tar --no-same-owner -xzf "$BUNDLE_PATH" -C "$STORE_PATH"
  else
    echo "ComfyUI bundle が無いため1から構築する (version: $COMFYUI_VERSION)"
    git clone --depth 1 --branch "$COMFYUI_VERSION" \
      https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
    "$BASE_PY" -m venv "$COMFYUI_DIR/venv"
    touch /run/mycomfy-bundle-from-scratch
  fi
fi
echo "ComfyUI commit: $(git -C "$COMFYUI_DIR" rev-parse HEAD)"

# 差分の補完（毎起動ごとに必ず実行する）
"$VENV_PY" -m pip install -r "$COMFYUI_DIR/requirements.txt"
