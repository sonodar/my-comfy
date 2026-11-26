#!/usr/bin/env bash
# モデルマニフェストの取得：SSM パラメータ（/mycomfy/model-manifest）から
# マニフェスト全体を取得し、引数で指定されたパスへ書き出す。
# モデル情報はこのマニフェスト1本に一元化しており、download-models.sh と
# sync-models.sh は、ここで書き出したファイルだけを読んで取得・同期する。
# 使い方: get-manifest.sh <書き出し先のパス>
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

MANIFEST="${1:?usage: get-manifest.sh <manifest-path>}"
mkdir -p "$(dirname "$MANIFEST")"

echo "model manifest: ssm parameter $MODEL_MANIFEST_PARAMETER"
aws ssm get-parameter --name "${MODEL_MANIFEST_PARAMETER:?MODEL_MANIFEST_PARAMETER is not set}" \
  --query "Parameter.Value" --output text > "$MANIFEST"
echo "model manifest written: $MANIFEST"
