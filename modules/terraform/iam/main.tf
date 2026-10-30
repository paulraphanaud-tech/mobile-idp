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

  # CodePipeline is scoped to the artifacts bucket alone.
  artifacts_object_arn = "${var.artifacts_bucket_arn}/*"

  codeartifact_enabled = var.codeartifact_domain_arn != "" && length(var.codeartifact_repository_arns) > 0
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
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/codebuild/${var.project_name}-*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/codebuild/${var.project_name}-*:*",
    ]
  }

  # CodeArtifact — emitted only when a domain and repositories are supplied.
  #
  # The previous version of this granted these actions on "*" unconditionally.
  # All three do support resource-level scoping (GetAuthorizationToken on a
  # domain ARN, the other two on repository ARNs), and nothing in this platform
  # uses CodeArtifact at all — gems come from rubygems.org and packages from
  # pub.dev. So the default is now to grant nothing.
  dynamic "statement" {
    for_each = local.codeartifact_enabled ? [1] : []

    content {
      sid    = "CodeArtifactToken"
      effect = "Allow"
      actions = [
        "codeartifact:GetAuthorizationToken",
      ]
      resources = [var.codeartifact_domain_arn]
    }
  }

  # GetAuthorizationToken is refused without this companion permission, and it
  # genuinely has no resource to scope to — the condition key is the intended
  # restriction. See "AWS CodeArtifact authentication and tokens".
  dynamic "statement" {
    for_each = local.codeartifact_enabled ? [1] : []

    content {
      sid    = "CodeArtifactServiceBearerToken"
      effect = "Allow"
      actions = [
        "sts:GetServiceBearerToken",
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "sts:AWSServiceName"
        values   = ["codeartifact.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.codeartifact_enabled ? [1] : []

    content {
      sid    = "CodeArtifactRead"
      effect = "Allow"
      actions = [
        "codeartifact:GetRepositoryEndpoint",
        "codeartifact:ReadFromRepository",
      ]
      resources = var.codeartifact_repository_arns
    }
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
  # S3 – the artifacts bucket only.
  #
  # This used to grant every action below, including DeleteObject, across all
  # of s3_bucket_arns — which is the match certificates bucket and the Android
  # keystore bucket as well as the artifacts bucket. CodePipeline reads neither:
  # it passes artifacts between stages and starts CodeBuild jobs, and it is
  # those jobs (under the CodeBuild role) that fetch signing material. Nothing
  # in modules/terraform/codepipeline/main.tf references either bucket.
  statement {
    sid    = "S3ArtifactsBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketVersioning",
      "s3:ListBucket",
    ]
    resources = [var.artifacts_bucket_arn]
  }

  statement {
    sid    = "S3ArtifactsObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:DeleteObject",
    ]
    resources = [local.artifacts_object_arn]
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
