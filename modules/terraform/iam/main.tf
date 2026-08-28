################################################################################
# IAM Roles for Flutter CI/CD IDP
#
# 1. CodeBuild service role  – used by build projects
# 2. CodePipeline service role – used by pipelines
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # Build object-level ARNs from the supplied bucket ARNs
  s3_object_arns = [for arn in var.s3_bucket_arns : "${arn}/*"]
}

# =============================================================================
# CodeBuild Service Role
# =============================================================================

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild_policy" {
  # S3 – bucket-level operations
  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = var.s3_bucket_arns
  }

  # S3 – object-level operations
  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = local.s3_object_arns
  }

  # Secrets Manager
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = var.secrets_arns
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogsAccess"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${var.project_name}-*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${var.project_name}-*:*",
    ]
  }

  # CodeArtifact
  statement {
    sid    = "CodeArtifactAccess"
    effect = "Allow"
    actions = [
      "codeartifact:GetAuthorizationToken",
      "codeartifact:GetRepositoryEndpoint",
      "codeartifact:ReadFromRepository",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${var.project_name}-codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_policy.json
}

# =============================================================================
# CodePipeline Service Role
# =============================================================================

data "aws_iam_policy_document" "codepipeline_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.project_name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codepipeline_policy" {
  # S3 – full access on artifacts bucket (first bucket ARN in the list is
  # assumed to be the artifacts bucket; the caller should pass it accordingly,
  # but we grant on all supplied ARNs for flexibility)
  statement {
    sid    = "S3FullAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = concat(var.s3_bucket_arns, local.s3_object_arns)
  }

  # CodeBuild
  statement {
    sid    = "CodeBuildAccess"
    effect = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]
    resources = [
      "arn:aws:codebuild:${local.region}:${local.account_id}:project/${var.project_name}-*",
    ]
  }

  # CodeStar Connections (source provider)
  dynamic "statement" {
    for_each = var.codestar_connection_arn != "" ? [1] : []

    content {
      sid    = "CodeStarConnectionAccess"
      effect = "Allow"
      actions = [
        "codestar-connections:UseConnection",
      ]
      resources = [var.codestar_connection_arn]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "${var.project_name}-codepipeline-policy"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}
