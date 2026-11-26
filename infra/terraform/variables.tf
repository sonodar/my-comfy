variable "aws_region" {
  description = "リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "リソース名の接頭辞"
  type        = string
  default     = "mycomfy"
}

variable "vpc_id" {
  description = "既存 VPC の ID（マウントターゲットとインスタンスを置く）"
  type        = string
}

variable "subnet_id" {
  description = "起動テンプレートから直接起動するときに使うパブリックサブネットの ID"
  type        = string
}

variable "subnet_ids" {
  description = "S3 Files のマウントターゲットと EC2 Fleet の起動候補に使うパブリックサブネットの ID 一覧（AZ ごとに1つ）"
  type        = list(string)
}

variable "instance_type" {
  description = "GPU インスタンスタイプ。決め打ちしない。選定条件は README 参照"
  type        = string
  default     = "g6e.xlarge"
}

variable "spot_fleet_instance_types" {
  description = "Spot Fleet のインスタンスタイプ候補"
  type        = set(string)
  default     = ["g6e.xlarge", "g6e.2xlarge"]
  nullable    = false

  validation {
    condition     = length(var.spot_fleet_instance_types) > 0
    error_message = "Spot Fleet のインスタンスタイプ候補を1つ以上指定してください。"
  }
}

variable "dlami_ssm_parameter" {
  description = "Deep Learning AMI を引く SSM パラメータ。AMI ID は固定値で書かない"
  type        = string
  default     = "/aws/service/deeplearning/ami/x86_64/oss-nvidia-driver-gpu-pytorch-2.12-ubuntu-24.04/latest/ami-id"
}

variable "comfyui_version" {
  description = "ComfyUI の版（GitHub リリースタグ）"
  type        = string
  default     = "v0.46.0"
}

variable "notify_topic_arn" {
  description = "notify-me の SNS トピック ARN（起動の成否通知先）。個人値のため tfvars で渡す"
  type        = string
}

variable "key_name" {
  description = "SSH 用キーペア名。不要なら null"
  type        = string
  default     = null
}

variable "bucket_name_prefix" {
  description = "S3 バケット名の接頭辞。後ろにアカウント ID とリージョンが付く"
  type        = string
  default     = "mycomfy"
}

variable "tailscale_auth_key" {
  description = "Tailscale 認証キー（Reusable + Ephemeral で発行したもの）。未設定ならプレースホルダで作られ、実値は後から AWS CLI で上書きできる"
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_auth_key_version" {
  description = "Tailscale 認証キーを Terraform で更新するときに増やす番号"
  type        = number
  nullable    = false
}

variable "workflow_setup_key" {
  description = "ワークフロー構築スクリプト一式（zip）のオブジェクトキー。置き場は専用バケット（workflow_setup.tf）。一式の中身はリポジトリでは管理しない"
  type        = string
  default     = "workflow-setup/mycomfy-workflow-setup.zip"
}

variable "workflow_setup_version" {
  description = "ワークフロー構築スクリプト一式のオブジェクトバージョン ID。空なら起動時点の最新を使う"
  type        = string
  default     = ""
}
