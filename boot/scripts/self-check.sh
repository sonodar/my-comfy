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
NOTIFY_DETAILS=()
HAS_WARNINGS=0
warn() {
  echo "WARN: $1"
  HAS_WARNINGS=1
  NOTIFY_DETAILS+=("⚠️ $2")
}
fail() {
  echo "FAIL: $1"
  FAILURES="$FAILURES $1"
  NOTIFY_DETAILS+=("❌ $2")
}

# --- GPU ---
if nvidia-smi >/dev/null 2>&1; then
  echo "gpu: ok ($(nvidia-smi --query-gpu=name --format=csv,noheader | head -1))"
else
  fail "gpu-not-visible" "GPU を認識できません。"
fi

# --- Tailscale（再起動直後は接続完了まで時間がかかるためリトライする） ---
TAILSCALE_OK=0
for i in $(seq 1 12); do
  if command -v tailscale >/dev/null 2>&1 \
    && tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
    TAILSCALE_OK=1
    break
  fi
  sleep 5
done
if [ "$TAILSCALE_OK" = "1" ]; then
  echo "tailscale: ok ($(tailscale ip -4 2>/dev/null | head -1))"
else
  fail "tailscale-not-connected" "Tailscale に接続できていません（登録済みマシンで起きた場合は、マシンの鍵の期限切れの可能性があります。管理画面でマシンの状態を確認してください）。"
fi

# --- インスタンスストア ---
STORE_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"
if mountpoint -q "$STORE_PATH"; then
  TEST_FILE="$STORE_PATH/.mycomfy-boot-check"
  if echo "check" > "$TEST_FILE" && [ "$(cat "$TEST_FILE")" = "check" ] && rm -f "$TEST_FILE"; then
    echo "instance-store: ok ($STORE_PATH)"
  else
    fail "instance-store-rw" "インスタンスストアに読み書きできません。"
  fi
else
  fail "instance-store-not-mounted" "インスタンスストアをマウントできていません。"
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
    fail "s3files-rw" "S3 Files に読み書きできません。"
  fi
else
  fail "s3files-not-mounted" "S3 Files をマウントできていません。"
fi

# S3 API での可視確認（警告のみ。反映遅延のため）
if [ "$S3_OK" = "1" ]; then
  MARKER="$S3_PATH/.mycomfy-boot-check-visible"
  echo "check" > "$MARKER"
  sleep 75
  if aws s3 ls "s3://$BUCKET_NAME/.mycomfy-boot-check-visible" >/dev/null 2>&1; then
    echo "s3-visible: ok"
  else
    warn "s3-visible: not yet visible via S3 API (sync delay; not fatal)" "S3 API から確認用ファイルをまだ参照できません。S3 Files からの反映に時間がかかっている可能性があります。"
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
  fail "comfyui-no-response" "ComfyUI から応答がありません。"
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

if [ "$STATUS" = ok ]; then
  printf '%s\n' ready > /run/mycomfy-boot-status || exit 1
fi

if [ -n "${NOTIFY_TOPIC_ARN:-}" ]; then
  if [ "$STATUS" = "failed" ]; then
    MESSAGE="mycomfy の起動チェックに失敗しました"
    LEVEL=error
  else
    MESSAGE="mycomfy の起動チェックが完了しました"
    LEVEL=info
    if [ "$HAS_WARNINGS" -eq 1 ]; then
      LEVEL=warn
    fi
  fi
  NOTIFIED_AT="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %Z')"
  MESSAGE="$MESSAGE
ホスト: $(hostname)
時刻: $NOTIFIED_AT"
  for detail in ${NOTIFY_DETAILS[@]+"${NOTIFY_DETAILS[@]}"}; do
    MESSAGE="$MESSAGE
$detail"
  done
  if NOTIFY_TOPIC_ARN="$NOTIFY_TOPIC_ARN" AWS_DEFAULT_REGION="$AWS_REGION" \
    /usr/local/bin/notify.sh "$MESSAGE" "$LEVEL"; then
    if [ "$STATUS" = failed ]; then
      printf '%s\n' failure-notified > /run/mycomfy-boot-status
    fi
  else
    echo "WARN: sns publish failed"
  fi
fi

echo "=== boot self-check end: $STATUS ==="
[ "$STATUS" = "ok" ]
