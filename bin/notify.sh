#!/usr/bin/env bash
set -euo pipefail

publish() {
  # 通知の失敗を握り潰さないため、間隔を空けて3回まで試す。
  # 全て失敗したら非ゼロで終わり、呼び出し側とログに失敗が残る。
  local attempt
  for attempt in 1 2 3; do
    if aws sns publish --topic-arn "${NOTIFY_TOPIC_ARN:?NOTIFY_TOPIC_ARN is required}" --message "$1"; then
      return 0
    fi
    echo "WARN: sns publish failed (attempt $attempt/3)" >&2
    if [ "$attempt" -lt 3 ]; then
      sleep $((attempt * 5))
    fi
  done
  return 1
}

message="$1"
case "${2:-error}" in
  error) publish "❌ $message" ;;
  warn) publish "⚠️ $message" ;;
  info) publish "ℹ️ $message" ;;
  *)
    printf 'Unknown notification level: %s\n' "$2" >&2
    exit 2
    ;;
esac
