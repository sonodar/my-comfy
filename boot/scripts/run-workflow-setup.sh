#!/usr/bin/env bash
# ワークフロー構築の受け口：専用バケットからスクリプト一式（zip）を取得し、
# 展開して入口の setup.sh を実行する。一式の中身はリポジトリでは管理しない。
# 版はオブジェクトバージョンで固定できる（WORKFLOW_SETUP_VERSION が空なら最新）。
# どの版で起動したかは、取得したオブジェクトのバージョン ID をログに残す。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

BUCKET="${WORKFLOW_SETUP_BUCKET:?WORKFLOW_SETUP_BUCKET is not set}"
KEY="${WORKFLOW_SETUP_KEY:?WORKFLOW_SETUP_KEY is not set}"
STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
DEST="$STORE_PATH/workflow-setup"
ZIP="$STORE_PATH/tmp/mycomfy-workflow-setup.zip"

export AWS_DEFAULT_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"
mkdir -p "$DEST" "$STORE_PATH/tmp"

if [ -n "${WORKFLOW_SETUP_VERSION:-}" ]; then
  echo "workflow setup bundle: s3://$BUCKET/$KEY (version: $WORKFLOW_SETUP_VERSION)"
  aws s3api get-object --bucket "$BUCKET" --key "$KEY" \
    --version-id "$WORKFLOW_SETUP_VERSION" "$ZIP" >/dev/null
else
  version_id="$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" \
    --query "VersionId" --output text 2>/dev/null || echo "unknown")"
  echo "workflow setup bundle: s3://$BUCKET/$KEY (latest, version: $version_id)"
  aws s3 cp "s3://$BUCKET/$KEY" "$ZIP" >/dev/null
fi

unzip -o "$ZIP" -d "$DEST" >/dev/null
bash "$DEST/setup.sh"
