#!/usr/bin/env bash
# インスタンスストア（エフェメラルディスク）を検出して固定パスへマウントする。
# デバイス名は決め打ちしない。device/model 文字列が
# "Amazon EC2 NVMe Instance Storage" のものをインスタンスストアとする。
# 起動のたびに走る前提：ファイルシステムが無ければ作り、あればそのまま使う。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

MOUNT_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"

DEVICE=""
for dev in /dev/nvme*n1; do
  [ -e "$dev" ] || continue
  base="$(basename "$dev")"
  model="$(cat "/sys/class/block/$base/device/model" 2>/dev/null || true)"
  if [ "$model" = "Amazon EC2 NVMe Instance Storage" ]; then
    DEVICE="$dev"
    break
  fi
done

if [ -z "$DEVICE" ]; then
  echo "FATAL: instance store device not found" >&2
  exit 1
fi

echo "instance store device: $DEVICE"

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  echo "no filesystem on $DEVICE; creating ext4"
  mkfs.ext4 -F "$DEVICE"
fi

mkdir -p "$MOUNT_PATH"
if ! mountpoint -q "$MOUNT_PATH"; then
  mount "$DEVICE" "$MOUNT_PATH"
fi

# 再起動後も同じパスに載るように fstab へ（重複登録しない）
if ! grep -q " $MOUNT_PATH " /etc/fstab 2>/dev/null; then
  echo "$DEVICE $MOUNT_PATH ext4 defaults,nofail 0 2" >> /etc/fstab
fi

df -h "$MOUNT_PATH"
echo "instance store mounted: $DEVICE -> $MOUNT_PATH"
