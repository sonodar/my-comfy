# 起動テンプレート (aws_launch_template)
#
# - インスタンスタイプは変数 (var.instance_type) で外出し。デフォルトは g6e.xlarge。
# - AMI は AWS 公式 Deep Learning AMI。AMI ID は SSM パラメータ参照で取得し、
#   コードに固定値を書かない。アーキテクチャの整合は plan 時に precondition で落とす。
# - 購入方式は起動時に EC2 Fleet で選ぶ。
# - user-data は boot/cloud-init/user-data.sh を templatefile で埋め込む。
#   user-data 自体は小さく、実処理は S3 に置いた boot/ バンドル (install.sh) が担う。

data "aws_ssm_parameter" "dlami" {
  name = var.dlami_ssm_parameter
}

data "aws_ec2_instance_type" "selected" {
  for_each      = setunion(toset([var.instance_type]), var.spot_fleet_instance_types)
  instance_type = each.key
}

resource "aws_launch_template" "this" {
  name_prefix   = "${var.project}-"
  image_id      = data.aws_ssm_parameter.dlami.value
  instance_type = var.instance_type

  tags = {
    S3FilesFileSystemId = aws_s3files_file_system.this.id
    FleetInstanceTypes  = join(",", sort(tolist(var.spot_fleet_instance_types)))
  }

  key_name = var.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  network_interfaces {
    subnet_id                   = var.subnet_id
    security_groups             = [aws_security_group.compute.id]
    associate_public_ip_address = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }

  user_data = base64encode(templatefile("${path.module}/../../boot/cloud-init/user-data.sh", {
    boot_bucket                      = aws_s3_bucket.this.bucket
    boot_key                         = aws_s3_object.boot_bundle.key
    aws_region                       = var.aws_region
    notify_topic_arn                 = var.notify_topic_arn
    s3_files_id                      = aws_s3files_file_system.this.id
    comfyui_version                  = var.comfyui_version
    bucket_name                      = aws_s3_bucket.this.bucket
    notify_script                    = file("${path.module}/../../bin/notify.sh")
    cloudwatch_agent_parameter       = aws_ssm_parameter.cloudwatch_agent.name
    tailscale_auth_key_parameter     = local.tailscale_auth_key_parameter
    comfyui_bundle_bucket            = aws_s3_bucket.this.bucket
    comfyui_bundle_key               = "comfyui-bundle/${var.comfyui_version}.tar.gz"
    workflow_setup_bucket            = aws_s3_bucket.workflow_setup.bucket
    workflow_setup_key               = var.workflow_setup_key
    workflow_setup_version           = var.workflow_setup_version
    stop_unused_services_script      = file("${path.module}/../../boot/cloud-init/stop-unused-services.sh")
    prepare_boot_dependencies_script = file("${path.module}/../../boot/cloud-init/prepare-boot-dependencies.sh")
    start_cloudwatch_agent_script    = file("${path.module}/../../boot/cloud-init/start-cloudwatch-agent.sh")
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = var.project
    }
  }

  # マウントターゲットが出来てからでないと、起動したインスタンスが S3 Files を解決できない
  depends_on = [
    aws_s3files_mount_target.this,
    aws_iam_role_policy.instance_boot_logs,
    aws_iam_role_policy_attachment.instance_ssm,
  ]

  lifecycle {
    precondition {
      condition = alltrue([
        for instance_type in data.aws_ec2_instance_type.selected :
        contains(instance_type.supported_architectures, "x86_64")
      ])
      error_message = "DLAMI の SSM パラメータは x86_64 用。arm64 のインスタンスタイプを使う場合は dlami_ssm_parameter も差し替えること。"
    }
  }
}
