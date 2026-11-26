output "launch_template_id" {
  description = "起動テンプレート ID"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "起動テンプレートの最新バージョン"
  value       = aws_launch_template.this.latest_version
}

output "spot_fleet_config" {
  description = "S3 Files のマウントターゲットがある AZ から Spot インスタンスを1台起動する EC2 Fleet 設定"
  value = {
    Type = "instant"
    SpotOptions = {
      AllocationStrategy = "capacity-optimized"
    }
    TargetCapacitySpecification = {
      TotalTargetCapacity       = 1
      DefaultTargetCapacityType = "spot"
    }
    LaunchTemplateConfigs = [{
      LaunchTemplateSpecification = {
        LaunchTemplateId = aws_launch_template.this.id
        Version          = tostring(aws_launch_template.this.latest_version)
      }
      Overrides = [
        for subnet_id in sort(keys(aws_s3files_mount_target.this)) : {
          SubnetId = subnet_id
        }
      ]
    }]
  }
}

output "data_bucket_name" {
  description = "S3 バケット名（モデル・成果物のデータ置き場。S3 Files の実体）"
  value       = aws_s3_bucket.this.bucket
}

output "source_bucket_name" {
  description = "S3 バケット名（ワークフロー構築スクリプト一式の置き場）"
  value       = aws_s3_bucket.workflow_setup.bucket
}

output "s3_files_id" {
  description = "S3 Files ファイルシステム ID"
  value       = aws_s3files_file_system.this.id
}

output "instance_role_arn" {
  description = "インスタンス用 IAM ロール ARN"
  value       = aws_iam_role.instance.arn
}

output "instance_security_group_id" {
  description = "インスタンス用セキュリティグループ ID"
  value       = aws_security_group.compute.id
}
