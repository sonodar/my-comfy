#!/usr/bin/env bash
# モデル同期：S3 の models/ からインスタンスストアへ、manifest のファイルを取り込む。
# SHA256 は manifest の各エントリの sha256 で照合する。manifest 全体は
# SSM パラメータ（/mycomfy/model-manifest）から取得する。
# 配置したファイルは ComfyUI の models/ 配下へシンボリックリンクし、ComfyUI から見えるようにする。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

BUCKET="${BUCKET_NAME:?BUCKET_NAME is not set}"
STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
MODELS_DIR="$STORE_PATH/models"
MANIFEST="/etc/mycomfy/manifest.yaml"
PY="/opt/pytorch/bin/python"

mkdir -p "$MODELS_DIR"

echo "model manifest: ssm parameter $MODEL_MANIFEST_PARAMETER"
aws ssm get-parameter --name "${MODEL_MANIFEST_PARAMETER:?MODEL_MANIFEST_PARAMETER is not set}" \
  --query "Parameter.Value" --output text > "$MANIFEST"

# manifest（YAML）を JSON 化する。PyYAML は ComfyUI の依存に入っている。
"$PY" - "$MANIFEST" <<'PYEOF' > /tmp/mycomfy-models.json
import json
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f)
print(json.dumps(data["models"]))
PYEOF

COUNT="$(jq 'length' /tmp/mycomfy-models.json)"
echo "models to sync: $COUNT"
for i in $(seq 0 $((COUNT - 1))); do
  FILE="$(jq -r ".[$i].file" /tmp/mycomfy-models.json)"
  DEST="$(jq -r ".[$i].dest" /tmp/mycomfy-models.json)"
  DEST_DIR="$MODELS_DIR/$DEST"
  mkdir -p "$DEST_DIR"
  TARGET="$DEST_DIR$FILE"

  REMOTE_SIZE="$(aws s3api head-object --bucket "$BUCKET" --key "models/$FILE" \
    --query "ContentLength" --output text 2>/dev/null || echo "")"
  if [ -z "$REMOTE_SIZE" ]; then
    echo "FATAL: s3://$BUCKET/models/$FILE が見つかりません" >&2
    exit 1
  fi

  if [ -f "$TARGET" ] && [ "$(stat -c %s "$TARGET")" = "$REMOTE_SIZE" ]; then
    echo "skip (already synced): $FILE ($REMOTE_SIZE bytes)"
  else
    echo "downloading: $FILE ($REMOTE_SIZE bytes) -> $TARGET"
    aws s3 cp "s3://$BUCKET/models/$FILE" "$TARGET" >/dev/null
    if [ "$(stat -c %s "$TARGET")" != "$REMOTE_SIZE" ]; then
      echo "FATAL: サイズ不一致: $FILE" >&2
      exit 1
    fi
  fi

  SHA="$(jq -r ".[$i].sha256 // empty" /tmp/mycomfy-models.json)"
  if [ -n "$SHA" ]; then
    echo "verifying sha256: $FILE"
    if ! echo "$SHA  $TARGET" | sha256sum -c - >/dev/null; then
      echo "FATAL: SHA256 不一致: $FILE" >&2
      exit 1
    fi
  fi

  # ComfyUI の models/ 配下へリンクする（実体はインスタンスストア側）
  LINK_DIR="/opt/ComfyUI/models/$DEST"
  mkdir -p "$LINK_DIR"
  ln -sfn "$TARGET" "$LINK_DIR$FILE"
done

df -h "$STORE_PATH"
echo "model sync done"
