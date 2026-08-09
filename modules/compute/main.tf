locals {
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "aws_instance" "host" {
  ami                                  = var.ami_id
  associate_public_ip_address          = true
  disable_api_stop                     = false
  disable_api_termination              = true
  iam_instance_profile                 = var.instance_profile_name
  instance_initiated_shutdown_behavior = "stop"
  instance_type                        = var.instance_type
  key_name                             = var.key_name
  monitoring                           = true
  subnet_id                            = var.subnet_id
  user_data = join("\n", [
    file("${path.module}/user-data.sh"),
    file("${path.module}/../ec2-startup/cloudflared-startup.sh"),
  ])
  user_data_replace_on_change = false
  vpc_security_group_ids      = var.security_group_ids

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
  }

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-host"
  })

  volume_tags = merge(local.tags, {
    Name = "${var.name_prefix}-root"
  })

  lifecycle {
    ignore_changes  = [ami]
    prevent_destroy = true
  }
}

resource "aws_eip" "host" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-host"
  })
}

resource "aws_eip_association" "host" {
  allocation_id = aws_eip.host.id
  instance_id   = aws_instance.host.id
}

resource "aws_ebs_volume" "application_data" {
  availability_zone    = var.availability_zone
  encrypted            = true
  final_snapshot       = true
  iops                 = var.data_volume_iops
  kms_key_id           = var.kms_key_arn
  multi_attach_enabled = false
  size                 = var.data_volume_size
  throughput           = var.data_volume_throughput
  type                 = "gp3"

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-application-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "application_data" {
  device_name = var.data_volume_device_name
  instance_id = aws_instance.host.id
  volume_id   = aws_ebs_volume.application_data.id
}
