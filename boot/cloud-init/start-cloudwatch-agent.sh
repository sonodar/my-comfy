#!/usr/bin/env bash
set -euo pipefail

cloudwatch_agent_parameter="$1"

echo 'CloudWatch Agent の設定を開始します。'
touch /var/log/mycomfy/install.log /var/log/mycomfy/boot-check.log
if [ ! -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  (
    agent_download_dir=$(mktemp -d)
    trap 'rm -rf -- "$agent_download_dir"' EXIT
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 --max-time 120 \
      "https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/$(dpkg --print-architecture)/latest/amazon-cloudwatch-agent.deb" \
      --output "$agent_download_dir/amazon-cloudwatch-agent.deb"
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y \
      "$agent_download_dir/amazon-cloudwatch-agent.deb"
  )
fi
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c "ssm:$cloudwatch_agent_parameter"
systemctl is-active --quiet amazon-cloudwatch-agent.service
