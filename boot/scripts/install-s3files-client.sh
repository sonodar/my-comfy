#!/usr/bin/env bash
set -euo pipefail

. /etc/os-release
EFS_UTILS_REPO="https://amazon-efs-utils.aws.com"
EFS_UTILS_KEYRING="/usr/share/keyrings/efs-utils.gpg"
curl -fsSL "$EFS_UTILS_REPO/efs-utils.gpg" -o "$EFS_UTILS_KEYRING"
chmod a+r "$EFS_UTILS_KEYRING"
printf 'deb [signed-by=%s] %s/repo/deb/%s/%s %s main\n' \
  "$EFS_UTILS_KEYRING" "$EFS_UTILS_REPO" "$ID" "$VERSION_ID" "$VERSION_ID" \
  > /etc/apt/sources.list.d/efs-utils.list
apt-get update --error-on=any
# amazon-efs-utils は mount -t s3files のヘルパを提供する（Ubuntu 24.04 の apt にある前提）
apt-get install -y amazon-efs-utils
