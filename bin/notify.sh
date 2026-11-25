#!/usr/bin/env bash
set -euo pipefail

publish() {
  aws sns publish --topic-arn "${NOTIFY_TOPIC_ARN:?NOTIFY_TOPIC_ARN is required}" --message "$1"
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
