terraform {
  backend "s3" {
    bucket       = "sonodar-private-data-prod"
    key          = "terraform/my-comfy/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
