# ワークフロー構築スクリプト一式の置き場（専用バケット）。
#
# リポジトリの担当は ComfyUI のセットアップまでで、ワークフローの構築
# （カスタムノード導入・モデル準備・ワークフロー配置）は S3 上のスクリプト
# 一式が担う。一式の中身はリポジトリでは管理せず、このバケットへ手作業で
# アップロードする。どの版のスクリプトで起動したかを追い、戻せるよう、
# バージョニングを有効にする。モデル置き場（S3 Files の付くバケット）と
# 分けるのは、そちらにバージョニングを付けると大容量のモデルオブジェクト
# まで版が溜まるため。

locals {
  workflow_setup_bucket_name = "${var.bucket_name_prefix}-workflow-setup-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "workflow_setup" {
  bucket = local.workflow_setup_bucket_name
}

resource "aws_s3_bucket_versioning" "workflow_setup" {
  bucket = aws_s3_bucket.workflow_setup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "workflow_setup" {
  bucket = aws_s3_bucket.workflow_setup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role_policy" "instance_workflow_setup" {
  name = "workflow-setup-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.workflow_setup.arn,
        "${aws_s3_bucket.workflow_setup.arn}/*"
      ]
    }]
  })
}
