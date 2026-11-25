#!/usr/bin/env bash
set -euo pipefail

cat > /etc/apt/apt.conf.d/99mycomfy-disable-periodic-updates <<'APT_CONFIG'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT_CONFIG
for unit in apt-daily.timer apt-daily-upgrade.timer; do
  if ! systemctl mask --now "$unit"; then
    printf '警告: %s を停止・無効化できませんでした。\n' "$unit" >&2
  fi
done

for apt_sources in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  if [ -f "$apt_sources" ]; then
    sed -i -E 's@http://(([^/[:space:]]+\.)?archive\.ubuntu\.com|security\.ubuntu\.com)/ubuntu@https://\1/ubuntu@g' "$apt_sources"
  fi
done

# aws cli が無ければ入れる（DLAMI には通常入っている）
if ! command -v aws >/dev/null || ! command -v unzip >/dev/null || ! command -v curl >/dev/null; then
  apt-get update --error-on=any
  apt-get install -y awscli unzip curl
fi
