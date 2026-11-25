#!/usr/bin/env bash
set -euo pipefail

COMFYUI_VERSION="$1"

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
