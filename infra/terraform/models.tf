# モデルまわり：モデル実体は S3 の models/ に置き、起動時にインスタンスストアへ
# 同期する。S3 に無いファイルは、初回起動時に取得元から取得して S3 へ保存する
# （boot/scripts/download-models.sh）。モデルを差し替えられるよう、取得元の URL・
# SHA256・台本生成プロンプトは SSM パラメータで管理し、差し替え時にコードの
# 変更が要らないようにする。

locals {
  # モデルファイルの取得元 URL（source_id→URL の JSON）を入れる SSM パラメータの名前（固定）。
  model_sources_parameter = "/mycomfy/model-sources"
  # モデルファイルの SHA256（ファイル名→ハッシュの JSON）を入れる SSM パラメータの名前（固定）。
  model_checksums_parameter = "/mycomfy/model-checksums"
  # 台本生成プロンプト（モデルに付随する文面で、モデルと一緒に差し替える）を入れる SSM パラメータの名前（固定）。
  script_generation_prompt_parameter = "/mycomfy/script-generation-prompt"
}

# 変数を設定して apply すればその値が書かれる。ローテーション時は対応する *_version を上げる。
# 変数未設定ならプレースホルダで作られる。実値も Terraform 経由で入れること
# （SSM へ直接書くと Terraform 側の版数とずれるため）。
resource "aws_ssm_parameter" "model_sources" {
  name             = local.model_sources_parameter
  description      = "Model file source URLs as JSON keyed by source_id in the model manifest"
  type             = "String"
  value_wo         = coalesce(var.model_sources, "{}")
  value_wo_version = var.model_sources_version
}

resource "aws_ssm_parameter" "model_checksums" {
  name             = local.model_checksums_parameter
  description      = "Model file checksums as JSON keyed by code-named file name"
  type             = "String"
  value_wo         = coalesce(var.model_checksums, "{}")
  value_wo_version = var.model_checksums_version
}

resource "aws_ssm_parameter" "script_generation_prompt" {
  name             = local.script_generation_prompt_parameter
  description      = "System prompt for script generation (prompt conversion)"
  type             = "SecureString"
  value_wo         = coalesce(var.script_generation_prompt, "REPLACE_ME")
  value_wo_version = var.script_generation_prompt_version
}

resource "aws_iam_role_policy" "instance_model_parameters" {
  name = "model-parameters-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:GetParameter"]
      Resource = [
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.model_sources_parameter}",
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.model_checksums_parameter}",
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.script_generation_prompt_parameter}",
      ]
    }]
  })
}

# --- 同期の設定ファイル（manifest とワークフロー）を S3 へ ---
# モデル実体（models/ 配下の大容量ファイル）は Terraform で管理しない。
# 初回起動時に download-models.sh が取得元から取得して S3 へ保存する。

resource "aws_s3_object" "config_manifest" {
  bucket = aws_s3_bucket.this.id
  key    = "config/manifest.yaml"
  source = "${path.module}/../../models/manifest.yaml"
  etag   = filemd5("${path.module}/../../models/manifest.yaml")
}

resource "aws_s3_object" "config_workflows" {
  for_each = fileset("${path.module}/../../workflows", "**/*.json")

  bucket = aws_s3_bucket.this.id
  key    = "config/workflows/${each.value}"
  source = "${path.module}/../../workflows/${each.value}"
  etag   = filemd5("${path.module}/../../workflows/${each.value}")
}
