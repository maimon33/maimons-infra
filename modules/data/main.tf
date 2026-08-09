locals {
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

resource "aws_kms_key" "platform" {
  description             = "Encrypts Maimons platform data, backups, and secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.name_prefix}-platform"
  target_key_id = aws_kms_key.platform.key_id
}

resource "aws_s3_bucket" "backups" {
  bucket = var.backup_bucket_name

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-backups"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.platform.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "archive-and-expire-noncurrent-objects"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
}

resource "aws_ecr_repository" "service" {
  for_each = var.ecr_repository_names

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.platform.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "IMMUTABLE"
  name                 = each.value

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  policy = jsonencode({
    rules = [
      {
        action       = { type = "expire" }
        description  = "Retain the newest 30 images"
        rulePriority = 1
        selection = {
          countNumber = 30
          countType   = "imageCountMoreThan"
          tagStatus   = "any"
        }
      }
    ]
  })
  repository = each.value.name
}

resource "aws_secretsmanager_secret" "service" {
  for_each = var.secret_names

  description             = "Secret container for ${each.value}; value populated outside Terraform"
  kms_key_id              = aws_kms_key.platform.arn
  name                    = "/platform/${var.environment}/${each.value}"
  recovery_window_in_days = 30

  tags = local.tags
}

