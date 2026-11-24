#!/usr/bin/env bash
# 起動の自己チェック。結果は JSON に残し、成否を notify-me の SNS へ publish する。
# S3 への反映遅延（書き込みの S3 コミットは約 60 秒）があるため、
# S3 API での可視確認だけは警告扱いとし、起動の合否にはしない。
set -uo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

LOG="/var/log/mycomfy/boot-check.log"
RESULT="/var/log/mycomfy/boot-check.json"
mkdir -p /var/log/mycomfy
exec >> "$LOG" 2>&1

echo "=== boot self-check start: $(date -Is) ==="

FAILURES=""
warn() { echo "WARN: $1"; }
fail() { echo "FAIL: $1"; FAILURES="$FAILURES $1"; }

# --- GPU ---
if nvidia-smi >/dev/null 2>&1; then
  echo "gpu: ok ($(nvidia-smi --query-gpu=name --format=csv,noheader | head -1))"
else
  fail "gpu-not-visible"
fi

# --- インスタンスストア ---
STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
if mountpoint -q "$STORE_PATH"; then
  TEST_FILE="$STORE_PATH/.mycomfy-boot-check"
  if echo "check" > "$TEST_FILE" && [ "$(cat "$TEST_FILE")" = "check" ] && rm -f "$TEST_FILE"; then
    echo "instance-store: ok ($STORE_PATH)"
  else
    fail "instance-store-rw"
  fi
else
  fail "instance-store-not-mounted"
fi

# --- S3 Files ---
S3_PATH="${S3FILES_MOUNT:-/mnt/s3files}"
S3_OK=0
if mountpoint -q "$S3_PATH"; then
  TEST_FILE="$S3_PATH/.mycomfy-boot-check-$(hostname)"
  if echo "check" > "$TEST_FILE" && [ "$(cat "$TEST_FILE")" = "check" ] && rm -f "$TEST_FILE"; then
    echo "s3files: ok ($S3_PATH, posix rw)"
    S3_OK=1
  else
    fail "s3files-rw"
  fi
else
  fail "s3files-not-mounted"
fi

# S3 API での可視確認（警告のみ。反映遅延のため）
if [ "$S3_OK" = "1" ]; then
  MARKER="$S3_PATH/.mycomfy-boot-check-visible"
  echo "check" > "$MARKER"
  sleep 75
  if aws s3 ls "s3://$BUCKET_NAME/.mycomfy-boot-check-visible" >/dev/null 2>&1; then
    echo "s3-visible: ok"
  else
    warn "s3-visible: not yet visible via S3 API (sync delay; not fatal)"
  fi
  rm -f "$MARKER"
fi

# --- ComfyUI ---
COMFYUI_OK=0
for i in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://127.0.0.1:8188/"; then
    echo "comfyui: ok (http://127.0.0.1:8188/ after ${i} tries)"
    COMFYUI_OK=1
    break
  fi
  sleep 5
done
if [ "$COMFYUI_OK" = "0" ]; then
  fail "comfyui-no-response"
fi

# --- 結果 ---
if [ -z "$FAILURES" ]; then
  STATUS="ok"
else
  STATUS="failed"
fi

cat > "$RESULT" <<EOF
{"status": "$STATUS", "failures": "$FAILURES", "host": "$(hostname)", "time": "$(date -Is)"}
EOF

MESSAGE="mycomfy boot check: status=$STATUS failures=[$FAILURES] host=$(hostname) time=$(date -Is)"
echo "$MESSAGE"

if [ -n "${NOTIFY_TOPIC_ARN:-}" ]; then
  aws sns publish --topic-arn "$NOTIFY_TOPIC_ARN" \
    --subject "mycomfy boot check: $STATUS" \
    --message "$MESSAGE" || echo "WARN: sns publish failed"
fi

echo "=== boot self-check end: $STATUS ==="
[ "$STATUS" = "ok" ]
