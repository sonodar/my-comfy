resource "aws_cloudwatch_log_group" "boot" {
  name              = "/${var.project}/boot"
  retention_in_days = 7
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
