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
  description = "既存パブリックサブネットの ID（インスタンスが実際に使うのはこの1つだけ。インターネットに出られること）"
  type        = string
}

variable "subnet_ids" {
  description = "S3 Files マウントターゲットを作るサブネットの ID 一覧（AZ ごとに1つ、a/c/d 分）。空なら subnet_id のみ"
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "GPU インスタンスタイプ。決め打ちしない。選定条件は README 参照"
  type        = string
  default     = "g6e.xlarge"
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
