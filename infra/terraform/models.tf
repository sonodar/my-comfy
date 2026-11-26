# モデルまわり：モデル実体は S3 の models/ に置き、起動時にインスタンスストアへ
# 同期する。S3 に無いファイルは、初回起動時に取得元から取得して S3 へ保存する
# （boot/scripts/download-models.sh）。モデルを差し替えられるよう、モデル情報は
# マニフェストに一元化し、その全体（取得元の URL・SHA256 を含む）を SSM パラメータで
# 管理する。台本生成プロンプトも SSM パラメータで管理し、差し替え時にコードの
# 変更が要らないようにする。

locals {
  # モデルマニフェスト全体（YAML。ファイルごとの取得元 URL・SHA256 を含む）を入れる
  # SSM パラメータの名前（固定）。モデル情報はこのマニフェスト1本に一元化する。
  model_manifest_parameter = "/mycomfy/model-manifest"
  # 台本生成プロンプト（モデルに付随する文面で、モデルと一緒に差し替える）を入れる SSM パラメータの名前（固定）。
  script_generation_prompt_parameter = "/mycomfy/script-generation-prompt"
}

# 変数を設定して apply すればその値が書かれる。ローテーション時は対応する *_version を上げる。
# 変数未設定ならプレースホルダで作られる。実値も Terraform 経由で入れること
# （SSM へ直接書くと Terraform 側の版数とずれるため）。
resource "aws_ssm_parameter" "model_manifest" {
  name             = local.model_manifest_parameter
  description      = "Model manifest YAML including source URL and SHA256 per file"
  type             = "String"
  value_wo         = coalesce(var.model_manifest, "models: []")
  value_wo_version = var.model_manifest_version
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
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.model_manifest_parameter}",
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.script_generation_prompt_parameter}",
      ]
    }]
  })
}

# --- 同期の設定ファイル（ワークフロー）を S3 へ ---
# モデル実体（models/ 配下の大容量ファイル）は Terraform で管理しない。
# 初回起動時に download-models.sh が取得元から取得して S3 へ保存する。
# マニフェストは S3 ではなく上記の SSM パラメータで配る（起動時にスクリプトが取得する）。

resource "aws_s3_object" "config_workflows" {
  for_each = fileset("${path.module}/../../workflows", "**/*.json")

  bucket = aws_s3_bucket.this.id
  key    = "config/workflows/${each.value}"
  source = "${path.module}/../../workflows/${each.value}"
  etag   = filemd5("${path.module}/../../workflows/${each.value}")
}
