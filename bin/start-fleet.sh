#!/usr/bin/env bash
set -euo pipefail

aws_json() {
  aws "$@" --output json --no-cli-pager
}

project="${MYCOMFY_PROJECT:-mycomfy}"
templates=$(aws_json ec2 describe-launch-templates \
  --filters "Name=launch-template-name,Values=$project-*")
if ! template=$(jq -ce '
  .LaunchTemplates
  | if length == 1 then .[0] else empty end
' <<< "$templates"); then
  printf '起動テンプレートを一意に特定できません。検索条件: %s-*\n' "$project" >&2
  exit 1
fi

if ! launch_config=$(jq -ce '
  def tag($key): [.Tags[]? | select(.Key == $key) | .Value][0];
  tag("S3FilesFileSystemId") as $file_system_id |
  tag("FleetInstanceTypes") as $instance_types |
  select(
    (.LaunchTemplateId | type == "string" and length > 0) and
    (.LatestVersionNumber | type == "number" and . > 0) and
    ($file_system_id | type == "string" and length > 0) and
    ($instance_types | type == "string" and test("^[a-z0-9-]+[.][a-z0-9]+(,[a-z0-9-]+[.][a-z0-9]+)*$"))
  ) |
  {
    templateId: .LaunchTemplateId,
    version: (.LatestVersionNumber | tostring),
    fileSystemId: $file_system_id,
    instanceTypes: ($instance_types | split(",") | unique)
  }
' <<< "$template"); then
  printf '%s\n' '起動テンプレートに Fleet の起動に必要な ID、バージョン、タグがありません。' >&2
  exit 1
fi

file_system_id=$(jq -r '.fileSystemId' <<< "$launch_config")
mount_targets=$(aws_json s3files list-mount-targets --file-system-id "$file_system_id")
if ! subnet_ids=$(jq -ce '
  [
    .mountTargets[]
    | select((.status | ascii_downcase) == "available")
    | .subnetId
    | select(type == "string" and length > 0)
  ] | unique | select(length > 0)
' <<< "$mount_targets"); then
  printf 'S3 Files %s に利用可能なマウントターゲットがありません。\n' "$file_system_id" >&2
  exit 1
fi

fleet_config=$(jq -cn --argjson launch "$launch_config" --argjson subnets "$subnet_ids" '
  {
    Type: "instant",
    TargetCapacitySpecification: {TotalTargetCapacity: 1},
    LaunchTemplateConfigs: [{
      LaunchTemplateSpecification: {
        LaunchTemplateId: $launch.templateId,
        Version: $launch.version
      },
      Overrides: [
        $subnets[] as $subnet | $launch.instanceTypes[]
        | {SubnetId: $subnet, InstanceType: .}
      ]
    }]
  }
')

# TODO: PoC 終了後は、Spot を先に試す処理を削除し、オンデマンドで起動する。
spot_config=$(jq -c '
  .TargetCapacitySpecification.DefaultTargetCapacityType = "spot"
  | .SpotOptions.AllocationStrategy = "capacity-optimized"
' <<< "$fleet_config")
spot_result=$(aws_json ec2 create-fleet --cli-input-json "$spot_config")

has_instance() {
  jq -e 'any(.Instances[]?.InstanceIds[]?; type == "string" and length > 0)' >/dev/null
}

if has_instance <<< "$spot_result"; then
  printf '%s\n' "$spot_result"
  exit 0
fi

printf '%s\n' "$spot_result" >&2
if ! jq -e '
  (.FleetId | type == "string" and length > 0) and (.Instances == [])
' >/dev/null <<< "$spot_result"; then
  exit 1
fi

printf '%s\n' 'Spot で起動できなかったため、オンデマンドで起動します。' >&2
on_demand_config=$(jq -c '
  .TargetCapacitySpecification.DefaultTargetCapacityType = "on-demand"
' <<< "$fleet_config")
on_demand_result=$(aws_json ec2 create-fleet --cli-input-json "$on_demand_config")
printf '%s\n' "$on_demand_result"
has_instance <<< "$on_demand_result"
