resource "aws_cloudwatch_log_group" "boot" {
  name              = "/${var.project}/boot"
  retention_in_days = 7
}

# --- S3 Files の export 失敗の継続検知 ---
# export の失敗はインスタンスが居なくてもファイルシステム側で起きるため、
# 起動時の self-check だけでは検知できない。メトリクスは公式ドキュメント
# （Monitoring S3 Files with Amazon CloudWatch）記載の名前空間 AWS/S3/Files。

resource "aws_cloudwatch_metric_alarm" "s3files_export_failures" {
  alarm_name          = "${var.project}-s3files-export-failures"
  alarm_description   = "S3 Files の export がリトライ不能な失敗になりました。ファイルシステムの状態（MISCONFIGURED）とサービスロールの権限を確認してください。"
  namespace           = "AWS/S3/Files"
  metric_name         = "ExportFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_s3files_file_system.this.id
  }

  alarm_actions = [var.notify_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "s3files_export_stuck" {
  alarm_name          = "${var.project}-s3files-export-stuck"
  alarm_description   = "S3 Files の export が1時間以上滞留しています。書き込みが S3 に届いていない可能性があります。ファイルシステムの状態（MISCONFIGURED）と FailedExports の推移を確認してください。"
  namespace           = "AWS/S3/Files"
  metric_name         = "ExportAge"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 3600
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_s3files_file_system.this.id
  }

  alarm_actions = [var.notify_topic_arn]
}

resource "aws_iam_role_policy" "instance_boot_logs" {
  name = "boot-logs"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.boot.arn}:log-stream:*"
    }]
  })
}

resource "aws_ssm_parameter" "cloudwatch_agent" {
  name = "/${var.project}/cloudwatch-agent"
  type = "String"
  value = jsonencode({
    logs = {
      force_flush_interval = 5
      logs_collected = {
        files = {
          collect_list = [
            for name, path in {
              user-data  = "/var/log/mycomfy-user-data.log"
              install    = "/var/log/mycomfy/install.log"
              boot-check = "/var/log/mycomfy/boot-check.log"
              } : {
              file_path       = path
              log_group_name  = aws_cloudwatch_log_group.boot.name
              log_stream_name = "{instance_id}/${name}"
            }
          ]
        }
      }
    }
  })
}
