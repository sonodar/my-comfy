#!/usr/bin/env bash
# S3 Files をマウントする。mount -t s3files（amazon-efs-utils のヘルパ）を使う。
# マウントターゲットは Terraform で作成済み（作成に数分かかるため、起動テンプレート側で依存を張っている）。
# 解決が遅れることがあるため、最大 5 回までリトライする。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

MOUNT_PATH="${S3FILES_MOUNT:-/mnt/s3files}"
FS_ID="${S3_FILES_ID:?S3_FILES_ID is not set}"

if ! command -v mount.s3files >/dev/null 2>&1; then
  echo "FATAL: mount.s3files helper not found (amazon-efs-utils が入っていない)" >&2
  exit 1
fi

mkdir -p "$MOUNT_PATH"

if ! mountpoint -q "$MOUNT_PATH"; then
  for i in 1 2 3 4 5; do
    if mount -t s3files "$FS_ID:/" "$MOUNT_PATH"; then
      break
    fi
    echo "mount attempt $i failed; retrying in 15s" >&2
    sleep 15
    if [ "$i" = "5" ]; then
      echo "FATAL: failed to mount S3 Files $FS_ID" >&2
      exit 1
    fi
  done
fi

if ! grep -q " $MOUNT_PATH " /etc/fstab 2>/dev/null; then
  echo "$FS_ID:/ $MOUNT_PATH s3files _netdev 0 0" >> /etc/fstab
fi

df -h "$MOUNT_PATH"
echo "S3 Files mounted: $FS_ID -> $MOUNT_PATH"
