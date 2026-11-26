#!/usr/bin/env bash
# モデル取得（初回のみ）：manifest のファイルが S3 の models/ に無ければ、
# 取得元からダウンロードして検証し、S3 へ保存する。S3 に揃っているファイルは
# 何もしない（同期は sync-models.sh の担当）。
# 取得元の URL は SSM パラメータ（/mycomfy/model-sources、source_id→URL の JSON）から引く。
# 1件でも取得したら、完了を notify で通知する。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

BUCKET="${BUCKET_NAME:?BUCKET_NAME is not set}"
STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
MANIFEST="/etc/mycomfy/manifest.yaml"
PY="/opt/pytorch/bin/python"

mkdir -p "$(dirname "$MANIFEST")"

echo "model manifest: s3://$BUCKET/config/manifest.yaml"
aws s3 cp "s3://$BUCKET/config/manifest.yaml" "$MANIFEST" >/dev/null

# manifest（YAML）を JSON 化する。PyYAML は ComfyUI の依存に入っている。
"$PY" - "$MANIFEST" <<'PYEOF' > /tmp/mycomfy-models.json
import json
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f)
print(json.dumps(data["models"]))
PYEOF

# 取得元（source_id→URL）。パラメータが無い・空なら取得はできない。
SOURCES="{}"
if [ -n "${MODEL_SOURCES_PARAMETER:-}" ]; then
  if VALUE="$(aws ssm get-parameter --name "$MODEL_SOURCES_PARAMETER" \
      --query "Parameter.Value" --output text 2>/dev/null)"; then
    SOURCES="$VALUE"
  fi
fi

# 照合用ハッシュ（任意）。パラメータが無い・空なら照合はスキップする。
EXPECTED="{}"
if [ -n "${MODEL_CHECKSUMS_PARAMETER:-}" ]; then
  if VALUE="$(aws ssm get-parameter --name "$MODEL_CHECKSUMS_PARAMETER" \
      --query "Parameter.Value" --output text 2>/dev/null)"; then
    EXPECTED="$VALUE"
  fi
fi

WORK="$(mktemp -d "$STORE_PATH/model-download.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

DOWNLOADED=""
COUNT="$(jq 'length' /tmp/mycomfy-models.json)"
echo "models to check: $COUNT"
for i in $(seq 0 $((COUNT - 1))); do
  FILE="$(jq -r ".[$i].file" /tmp/mycomfy-models.json)"
  SOURCE_ID="$(jq -r ".[$i].source_id" /tmp/mycomfy-models.json)"

  if aws s3api head-object --bucket "$BUCKET" --key "models/$FILE" >/dev/null 2>&1; then
    echo "skip (already in S3): $FILE"
    continue
  fi

  URL="$(jq -r --arg id "$SOURCE_ID" '.[$id] // empty' <<< "$SOURCES")"
  if [ -z "$URL" ]; then
    echo "FATAL: $FILE の取得元（source_id: $SOURCE_ID）が SSM パラメータ ${MODEL_SOURCES_PARAMETER:-（未設定）} にありません" >&2
    exit 1
  fi

  echo "downloading: $FILE (source_id: $SOURCE_ID)"
  curl -fL --retry 3 -o "$WORK/$FILE" "$URL"

  SHA="$(jq -r --arg f "$FILE" '.[$f] // empty' <<< "$EXPECTED")"
  if [ -n "$SHA" ]; then
    echo "verifying sha256: $FILE"
    if ! echo "$SHA  $WORK/$FILE" | sha256sum -c - >/dev/null; then
      echo "FATAL: SHA256 不一致: $FILE" >&2
      exit 1
    fi
  else
    echo "no checksum registered for $FILE; computed: $(sha256sum "$WORK/$FILE" | cut -d' ' -f1)"
  fi

  echo "saving to S3: s3://$BUCKET/models/$FILE"
  aws s3 cp "$WORK/$FILE" "s3://$BUCKET/models/$FILE" >/dev/null
  rm -f "$WORK/$FILE"
  DOWNLOADED="${DOWNLOADED:+$DOWNLOADED、}$FILE"
done

if [ -n "$DOWNLOADED" ]; then
  echo "model download done: $DOWNLOADED"
  /usr/local/bin/notify.sh "モデル取得が完了しました。初回取得として配布元から取得し、S3 に保存しました：${DOWNLOADED}。次回以降の起動では S3 から同期します。運用者の対応は不要です。" info \
    || echo "WARN: モデル取得完了の通知に失敗しました"
else
  echo "model download: nothing to do (all models already in S3)"
fi
