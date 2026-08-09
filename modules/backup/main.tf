data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      identifiers = ["backup.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "backup" {
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
  name               = "${var.name_prefix}-backup"

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup.name
}

resource "aws_iam_role_policy_attachment" "restore" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.backup.name
}

resource "aws_backup_vault" "platform" {
  kms_key_arn = var.kms_key_arn
  name        = "${var.name_prefix}-platform"

  tags = var.tags
}

resource "aws_backup_vault_lock_configuration" "platform" {
  backup_vault_name   = aws_backup_vault.platform.name
  min_retention_days  = var.retention_days
  changeable_for_days = 3
}

resource "aws_backup_plan" "platform" {
  name = "${var.name_prefix}-daily"

  rule {
    completion_window        = 180
    enable_continuous_backup = false
    rule_name                = "daily"
    schedule                 = var.schedule
    start_window             = 60
    target_vault_name        = aws_backup_vault.platform.name

    lifecycle {
      delete_after = var.retention_days
    }
  }

  tags = var.tags
}

resource "aws_backup_selection" "platform" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.name_prefix}-platform"
  plan_id      = aws_backup_plan.platform.id
  resources    = var.resource_arns
}

