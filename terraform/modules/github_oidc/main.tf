locals {
  create_provider = var.github_oidc_provider_arn == ""
  provider_arn    = local.create_provider ? aws_iam_openid_connect_provider.github[0].arn : var.github_oidc_provider_arn
}

# Thumbprints oficiais da AWS para token.actions.githubusercontent.com
data "aws_iam_openid_connect_provider" "existing" {
  count = local.create_provider ? 0 : 1
  arn   = var.github_oidc_provider_arn
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = merge(var.tags, {
    Name = "${var.project_name}-github-oidc"
  })
}

###############################################################################
# Role assumida pelos workflows do GitHub Actions (OIDC federation)
###############################################################################

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:pull_request",
        "repo:${var.github_repository}:environment:*"
      ]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.project_name}-github-ci-role"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  max_session_duration = 3600

  tags = merge(var.tags, {
    Name = "${var.project_name}-github-ci-role"
  })
}

data "aws_iam_policy_document" "ci_permissions" {
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ci_permissions" {
  name   = "${var.project_name}-github-ci-permissions"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_permissions.json
}
