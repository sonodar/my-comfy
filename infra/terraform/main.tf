# S3 バケット、S3 Files、セキュリティグループ、IAM ロール。
# 起動テンプレート本体は launch_template.tf。

data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

locals {
  bucket_name = "${var.bucket_name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  # Tailscale 認証キーを入れる SSM パラメータの名前（固定）。
  # パラメータの器（SecureString、暗号化キーは既定の aws/ssm）は Terraform が作り、
  # 値（Reusable で発行した認証キー）は apply の後に Terraform の外で差し替える。
  # 認証キーは新規インスタンスの参加登録に使う。この構成ではインスタンスを作り直すたびに
  # 登録が発生する（同じインスタンスの停止→起動では再登録しない）ため、実質は起動のたびに要る。
  # キーは Reusable かつ Ephemeral で発行すること（Ephemeral のマシンはオフラインになると
  # tailnet から自動で消えるので、作り直しても管理画面に残骸が溜まらない）。
  # キー自体の期限（既定90日）が切れても登録済みマシンの接続には影響しないが、新しい
  # インスタンスを作るときに切れていたら登録が失敗する。その場合は新しいキーを発行して
  # このパラメータの値を差し替える（コード変更・apply は不要）。
  tailscale_auth_key_parameter = "/${var.project}/tailscale-auth-key"
}

# --- S3 バケット（成果物置き場。S3 Files のファイルシステムもこのバケットに付く） ---

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled" # S3 Files の必須条件
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- S3 Files：同期用のサービスロール（elasticfilesystem.amazonaws.com が assume する） ---

resource "aws_iam_role" "s3files_service" {
  name_prefix = "${var.project}-s3files-service-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "elasticfilesystem.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3files:${var.aws_region}:${data.aws_caller_identity.current.account_id}:file-system/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "s3files_service_s3" {
  name = "s3-access"
  role = aws_iam_role.s3files_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketVersioning"
      ]
      Resource = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "s3files_service_events" {
  name = "eventbridge"
  role = aws_iam_role.s3files_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "events:PutRule",
        "events:PutTargets",
        "events:DeleteRule",
        "events:RemoveTargets",
        "events:DescribeRule",
        "events:ListTargetsByRule"
      ]
      Resource = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/DO-NOT-DELETE-S3-Files*"
    }]
  })
}

# --- サービスクオータ：G 系スポットの vCPU 上限（デフォルト 0 のアカウントがあるため引き上げを申請する） ---
# 承認は AWS 側の審査次第で、apply が承認待ちで止まることがある。値は vCPU 数（g6e.xlarge = 4）。
resource "aws_servicequotas_service_quota" "spot_g_vt" {
  service_code = "ec2"
  quota_code   = "L-3819A6DF" # All G and VT Spot Instance Requests
  value        = 8
}

# --- S3 Files：ファイルシステムとマウントターゲット（subnet_ids の各 AZ に作る） ---

resource "aws_s3files_file_system" "this" {
  bucket   = aws_s3_bucket.this.arn
  role_arn = aws_iam_role.s3files_service.arn

  depends_on = [
    aws_iam_role_policy.s3files_service_s3,
    aws_iam_role_policy.s3files_service_events
  ]
}

resource "aws_security_group" "s3files" {
  name_prefix = "${var.project}-s3files-"
  description = "S3 Files mount targets"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "s3files_within_vpc" {
  description       = "Return traffic within VPC"
  security_group_id = aws_security_group.s3files.id
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  ip_protocol       = "-1"
}

resource "aws_s3files_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_s3files_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.s3files.id]
}

# --- インスタンス側：セキュリティグループと IAM ロール ---

resource "aws_security_group" "compute" {
  name_prefix = "${var.project}-compute-"
  description = "GPU instance (no inbound)"
  vpc_id      = var.vpc_id

  # インバウンドは開けない。Tailscale 経由で使う前提（Tailscale 参加は別途）。
}

resource "aws_vpc_security_group_egress_rule" "compute_https" {
  description       = "HTTPS egress (apt, git, pip, AWS APIs)"
  security_group_id = aws_security_group.compute.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "compute_tailscale" {
  description       = "Tailscale direct connection (WireGuard)"
  security_group_id = aws_security_group.compute.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 41641
  to_port           = 41641
  ip_protocol       = "udp"
}

# SG 同士を参照するルールは、相互参照の循環を避けるため単独リソースで定義する
resource "aws_vpc_security_group_ingress_rule" "s3files_nfs_from_compute" {
  description                  = "NFS from compute"
  security_group_id            = aws_security_group.s3files.id
  referenced_security_group_id = aws_security_group.compute.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "compute_nfs_to_s3files" {
  description                  = "NFS to S3 Files mount targets"
  security_group_id            = aws_security_group.compute.id
  referenced_security_group_id = aws_security_group.s3files.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_iam_role" "instance" {
  name_prefix = "${var.project}-instance-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "instance_s3" {
  name = "s3-access"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "instance_notify" {
  name = "notify"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = var.notify_topic_arn
    }]
  })
}

# パラメータの器だけを Terraform で作る。値はダミーで、実キーは Terraform の外で
# （AWS アプリやコンソールから）差し替える。ignore_changes により、差し替え後の値が
# tfstate に取り込まれることはない
resource "aws_ssm_parameter" "tailscale_auth_key" {
  name        = local.tailscale_auth_key_parameter
  description = "Tailscale auth key for instance registration (the value is set outside Terraform)"
  type        = "SecureString"
  value       = "placeholder-set-the-real-key-outside-terraform"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_role_policy" "instance_tailscale_key" {
  name = "tailscale-key-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.tailscale_auth_key_parameter}"
    }]
  })
}

resource "aws_iam_role_policy" "instance_s3files" {
  name = "s3files-client"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3files:ClientMount",
        "s3files:ClientWrite",
        "s3files:ClientRootAccess",
        "s3files:GetFileSystem",
        "s3files:GetMountTarget"
      ]
      Resource = aws_s3files_file_system.this.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.project}-instance-"
  role        = aws_iam_role.instance.name
}

# --- 起動用バンドル（boot/ 一式を zip にして S3 へ。user-data が取ってくる） ---

data "archive_file" "boot" {
  type        = "zip"
  source_dir  = "${path.module}/../../boot"
  output_path = "${path.module}/.terraform/boot.zip"
}

resource "aws_s3_object" "boot_bundle" {
  bucket = aws_s3_bucket.this.id
  key    = "boot/mycomfy-boot.zip"
  source = data.archive_file.boot.output_path
  etag   = data.archive_file.boot.output_md5
}
