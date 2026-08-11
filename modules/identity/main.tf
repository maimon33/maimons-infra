data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "host" {
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    effect = "Allow"
    resources = [
      var.backup_bucket_arn,
      "${var.backup_bucket_arn}/*",
    ]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    effect    = "Allow"
    resources = values(var.ecr_repository_arns)
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    effect    = "Allow"
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []

    content {
      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      effect    = "Allow"
      resources = values(var.secret_arns)
    }
  }

  statement {
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    effect    = "Allow"
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role" "host" {
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  name               = "${var.name_prefix}-host"

  tags = var.tags
}

resource "aws_iam_role_policy" "host" {
  name   = "platform-data-access"
  policy = data.aws_iam_policy_document.host.json
  role   = aws_iam_role.host.id
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.host.name
}

resource "aws_iam_role_policy_attachment" "host_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.host.name
}

resource "aws_iam_instance_profile" "host" {
  name = "${var.name_prefix}-host"
  role = aws_iam_role.host.name

  tags = var.tags
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.manage_github_oidc_provider ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["227203b5317f3818cab5b5ce596132bf36748c0e"]
  url             = "https://token.actions.githubusercontent.com"

  tags = var.tags
}

data "aws_iam_policy_document" "github_oidc_assume" {
  count = var.manage_github_oidc_provider ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
      type        = "Federated"
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:maimon33/*"]
    }
  }
}

data "aws_iam_policy_document" "github_ssm" {
  statement {
    actions = [
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:GetConnectionStatus",
    ]
    effect    = "Allow"
    resources = ["arn:aws:ssm:*:*:document/AWS-StartInteractiveCommand"]
  }

  statement {
    actions = [
      "ec2:DescribeInstances",
    ]
    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_role" "github_ssm" {
  count = var.manage_github_oidc_provider ? 1 : 0

  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume[0].json
  name               = "${var.name_prefix}-github-ssm"

  tags = var.tags
}

resource "aws_iam_role_policy" "github_ssm" {
  count = var.manage_github_oidc_provider ? 1 : 0

  name   = "ssm-session-manager"
  policy = data.aws_iam_policy_document.github_ssm.json
  role   = aws_iam_role.github_ssm[0].id
}
