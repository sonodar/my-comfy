#!/usr/bin/env bash
# インスタンスストア（エフェメラルディスク）を検出して固定パスへマウントする。
# モデル名の前後に空白があっても検出できるように、
# "Amazon EC2 NVMe Instance Storage" を含む NVMe デバイスを探す。
# 起動のたびに走る前提：ファイルシステムが無ければ作り、あればそのまま使う。
set -euo pipefail

# shellcheck disable=SC1091
. /etc/mycomfy/env

MOUNT_PATH="${INSTANCE_STORE_PATH:-/mnt/instance-store}"

INSTANCE_STORE_DEVICES=()
for dev in /dev/nvme*n1; do
  [ -e "$dev" ] || continue
  base="$(basename "$dev")"
  model="$(cat "/sys/class/block/$base/device/model" 2>/dev/null || true)"
  if [[ "$model" == *"Amazon EC2 NVMe Instance Storage"* ]]; then
    INSTANCE_STORE_DEVICES+=("$dev")
  fi
done

if [ "${#INSTANCE_STORE_DEVICES[@]}" -eq 0 ]; then
  echo "FATAL: instance store device not found" >&2
  exit 1
fi

if [ "${#INSTANCE_STORE_DEVICES[@]}" -gt 1 ]; then
  echo "FATAL: multiple instance store devices found: ${INSTANCE_STORE_DEVICES[*]}" >&2
  exit 1
fi

DEVICE="${INSTANCE_STORE_DEVICES[0]}"
echo "instance store device: $DEVICE"

DLAMI_MOUNT_PATH="/opt/dlami/nvme"
if DLAMI_MOUNT="$(findmnt -nro MAJ:MIN,FSROOT --mountpoint "$DLAMI_MOUNT_PATH")"; then
  DLAMI_DEVICE_ID="${DLAMI_MOUNT%% *}"
  INSTANCE_STORE_DEVICE_IDS="$(lsblk -nro MAJ:MIN "$DEVICE")"
  if ! grep -Fxq "$DLAMI_DEVICE_ID" <<< "$INSTANCE_STORE_DEVICE_IDS"; then
    echo "FATAL: $DLAMI_MOUNT_PATH is not backed by $DEVICE" >&2
    exit 1
  fi

  mkdir -p "$MOUNT_PATH"
  if CURRENT_MOUNT="$(findmnt -nro MAJ:MIN,FSROOT --mountpoint "$MOUNT_PATH")"; then
    if [ "$CURRENT_MOUNT" != "$DLAMI_MOUNT" ]; then
      echo "FATAL: $MOUNT_PATH is mounted from a different filesystem" >&2
      exit 1
    fi
  else
    mount --bind "$DLAMI_MOUNT_PATH" "$MOUNT_PATH"
  fi
  df -h "$MOUNT_PATH"
  exit 0
fi

if [ "$(lsblk -dno FSTYPE "$DEVICE")" = LVM2_member ]; then
  echo "FATAL: instance store uses LVM but $DLAMI_MOUNT_PATH is not mounted" >&2
  exit 1
fi

probe_status=0
probe_output="$(blkid -p "$DEVICE" 2>&1)" || probe_status=$?
case "$probe_status" in
  0) ;;
  2)
    if [ -n "$probe_output" ]; then
      printf 'FATAL: cannot inspect instance store: %s\n' "$probe_output" >&2
      exit "$probe_status"
    fi
    python3 - "$DEVICE" <<'PY'
import ctypes
import os
import sys

device = sys.argv[1]
blkid = ctypes.CDLL("libblkid.so.1")
blkid.blkid_new_probe_from_filename.argtypes = [ctypes.c_char_p]
blkid.blkid_new_probe_from_filename.restype = ctypes.c_void_p
blkid.blkid_probe_enable_superblocks.argtypes = [ctypes.c_void_p, ctypes.c_int]
blkid.blkid_probe_enable_partitions.argtypes = [ctypes.c_void_p, ctypes.c_int]
blkid.blkid_do_safeprobe.argtypes = [ctypes.c_void_p]
blkid.blkid_free_probe.argtypes = [ctypes.c_void_p]
blkid.blkid_free_probe.restype = None

probe = blkid.blkid_new_probe_from_filename(os.fsencode(device))
if not probe:
    sys.exit(f"FATAL: cannot open {device} for probing")
try:
    if (blkid.blkid_probe_enable_superblocks(probe, 1) != 0
            or blkid.blkid_probe_enable_partitions(probe, 1) != 0):
        sys.exit(f"FATAL: cannot configure signature probing for {device}")
    result = blkid.blkid_do_safeprobe(probe)
    if result != 1:
        sys.exit(f"FATAL: cannot verify that {device} has no signatures (probe result {result})")
finally:
    blkid.blkid_free_probe(probe)
PY
    echo "no filesystem on $DEVICE; creating ext4"
    mkfs.ext4 "$DEVICE" </dev/null
    ;;
  *)
    echo "FATAL: cannot identify the filesystem on $DEVICE (blkid exit $probe_status)" >&2
    exit "$probe_status"
    ;;
esac

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
