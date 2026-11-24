#!/usr/bin/env bash
# 起動処理の失敗を notify-me の SNS トピックへ publish する。
# systemd の OnFailure から呼ばれる想定: notify-failure.sh <unit-name>
#
# 接続先は個人値のためコードに書かない。
# /etc/mycomfy/notify.env に NOTIFY_TOPIC_ARN を定義する（Terraform / SSM 側で配布）。
set -euo pipefail

ENV_FILE="${MYCOMFY_NOTIFY_ENV:-/etc/mycomfy/notify.env}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

UNIT="${1:-不明}"
DETAIL="${2:-}"
HOST="$(hostname)"
NOTIFIED_AT="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %Z')"
MESSAGE="起動処理に失敗しました。
対象: $UNIT
ホスト: $HOST
時刻: $NOTIFIED_AT"
if [ -n "$DETAIL" ]; then
  MESSAGE="$MESSAGE
$DETAIL"
fi

if [ -z "${NOTIFY_TOPIC_ARN:-}" ]; then
  echo "NOTIFY_TOPIC_ARN is not set; cannot notify" >&2
  exit 1
fi

if [ -n "${AWS_REGION:-}" ]; then
  export AWS_DEFAULT_REGION="$AWS_REGION"
fi

aws sns publish \
  --topic-arn "$NOTIFY_TOPIC_ARN" \
  --subject "mycomfy の起動に失敗しました" \
  --message "$MESSAGE"
