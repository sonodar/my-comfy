output "launch_template_id" {
  description = "起動テンプレート ID"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "起動テンプレートの最新バージョン"
  value       = aws_launch_template.this.latest_version
}

output "bucket_name" {
  description = "S3 バケット名（成果物置き場）"
  value       = aws_s3_bucket.this.bucket
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
