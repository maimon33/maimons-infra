locals {
  service_names = setunion(
    toset(keys(var.deployment_principal_arns)),
    toset(keys(var.github_repository_subjects)),
  )
}

data "aws_iam_policy_document" "assume_role" {
  for_each = local.service_names

  dynamic "statement" {
    for_each = length(lookup(var.deployment_principal_arns, each.key, [])) > 0 ? [1] : []

    content {
      actions = ["sts:AssumeRole"]
      effect  = "Allow"

      principals {
        identifiers = var.deployment_principal_arns[each.key]
        type        = "AWS"
      }
    }
  }

  dynamic "statement" {
    for_each = var.github_oidc_provider_arn != null && length(lookup(var.github_repository_subjects, each.key, [])) > 0 ? [1] : []

    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      effect  = "Allow"

      principals {
        identifiers = [var.github_oidc_provider_arn]
        type        = "Federated"
      }

      condition {
        test     = "StringEquals"
        values   = ["sts.amazonaws.com"]
        variable = "token.actions.githubusercontent.com:aud"
      }

      condition {
        test     = "StringLike"
        values   = var.github_repository_subjects[each.key]
        variable = "token.actions.githubusercontent.com:sub"
      }
    }
  }
}

resource "aws_iam_role" "service" {
  for_each = local.service_names

  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json
  name               = "${var.name_prefix}-${each.key}-deploy"

  tags = merge(var.tags, {
    Service = each.key
  })
}

data "aws_iam_policy_document" "service" {
  for_each = local.service_names

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    effect    = "Allow"
    resources = [var.ecr_repository_arns[each.key]]
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    actions = [
      "ssm:SendCommand",
    ]
    effect = "Allow"
    resources = [
      var.instance_arn,
      "arn:aws:ssm:*::document/AWS-RunShellScript",
    ]
  }

  statement {
    actions = [
      "ssm:CancelCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "service" {
  for_each = local.service_names

  name   = "deploy-${each.key}"
  policy = data.aws_iam_policy_document.service[each.key].json
  role   = aws_iam_role.service[each.key].id
}
