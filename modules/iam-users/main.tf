terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Service deployment IAM users
resource "aws_iam_user" "service_user" {
  for_each = toset(var.services)

  name = "${var.name_prefix}-${each.value}-deploy-user"
  tags = merge(var.tags, {
    Service = each.value
    Purpose = "CI/CD Deployment Credentials"
  })
}

# Access keys for each service user
resource "aws_iam_access_key" "service_key" {
  for_each = toset(var.services)

  user       = aws_iam_user.service_user[each.value].name
  depends_on = [aws_iam_user_policy.service_policy]

  lifecycle {
    create_before_destroy = true
  }
}

# Service deployment policy
resource "aws_iam_user_policy" "service_policy" {
  for_each = toset(var.services)

  name = "${var.name_prefix}-${each.value}-deploy"
  user = aws_iam_user.service_user[each.value].name
  policy = templatefile("${path.module}/policies/${each.value}-deploy.json", {
    ECR_REPO_ARN  = var.ecr_repository_arns[each.value]
    SECRET_ARN    = var.secret_arns[each.value]
    KMS_KEY_ARN   = var.kms_key_arn
    S3_BUCKET_ARN = var.s3_backup_bucket_arn
  })
}
