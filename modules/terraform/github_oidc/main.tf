################################################################################
# GitHub Actions → AWS, without static credentials
#
# An IAM role that GitHub Actions jobs assume through OpenID Connect. The trust
# policy only accepts jobs bound to an allowed GitHub *environment* of an
# allowed repository ("repo:<owner>/<repo>:environment:<env>"), so a workflow
# on a random branch, or a fork's PR, cannot assume it.
#
# Permissions are the read-only subset of the CodeBuild role that a signed iOS
# build needs: GetSecretValue on the fastlane secrets, and read on the match
# bucket. CI runs match readonly, so it never needs to write certificates.
################################################################################

locals {
  oidc_host = "token.actions.githubusercontent.com"

  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  allowed_subjects = flatten([
    for repo in var.repositories : [
      for env in var.github_environments : "repo:${repo}:environment:${env}"
    ]
  ])
}

# One per AWS account and URL. If another stack already created it, set
# create_oidc_provider = false and pass its ARN as existing_oidc_provider_arn —
# a second one fails the apply with EntityAlreadyExists.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate against its own trust store and ignores
  # these, but older AWS provider versions still require the argument.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.project_name}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  tags                 = var.tags

  lifecycle {
    precondition {
      condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != ""
      error_message = "Set existing_oidc_provider_arn when create_oidc_provider = false."
    }
    precondition {
      condition     = length(var.repositories) > 0
      error_message = "repositories must list at least one owner/repo."
    }
  }
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "ReadFastlaneSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }

  statement {
    sid       = "ListMatchBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.match_bucket_arn]
  }

  statement {
    sid       = "ReadMatchObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.match_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.permissions.json
}
