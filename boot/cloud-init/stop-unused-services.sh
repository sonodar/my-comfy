#!/usr/bin/env bash
set -euo pipefail

for unit in docker.socket docker.service containerd.service fwupd-refresh.timer; do
  if ! systemctl mask --now "$unit"; then
    printf '警告: %s を停止・無効化できませんでした。\n' "$unit" >&2
  fi
done
