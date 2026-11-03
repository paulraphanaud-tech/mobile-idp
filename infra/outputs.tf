# =============================================================================
# S3
# =============================================================================
output "match_bucket_name" {
  description = "S3 bucket for Fastlane Match certificates. null when match_storage_mode = \"git\"."
  value       = module.s3.match_bucket_name
}

# Where Match reads certificates from in CI. Also the place the cross-variable
# checks live: a variable validation cannot reference another variable before
# Terraform 1.9, and failing the plan here beats a Mac-fleet build failing on
# "MATCH_STORAGE_MODE=git needs MATCH_GIT_URL" twenty minutes in.
output "match_storage" {
  description = "Fastlane Match storage: mode, and the bucket or repository CI reads."
  value = {
    mode       = var.match_storage_mode
    s3_bucket  = module.s3.match_bucket_name
    git_url    = local.match_uses_git ? var.match_git_url : null
    git_branch = local.match_uses_git ? var.match_git_branch : null
    git_auth   = local.match_uses_git ? var.match_git_auth : null
  }

  precondition {
    condition     = !local.match_uses_git || trimspace(var.match_git_url) != ""
    error_message = "match_storage_mode = \"git\" requires match_git_url."
  }

  precondition {
    condition = !local.match_uses_git || (
      var.match_git_auth == "ssh"
      ? can(regex("^(git@|ssh://)", var.match_git_url))
      : can(regex("^https://", var.match_git_url))
    )
    error_message = "match_git_url does not fit match_git_auth: \"https\" needs an https:// URL, \"ssh\" needs git@host:org/repo.git or ssh://..."
  }
}

output "keystore_bucket_name" {
  description = "S3 bucket for Android keystores"
  value       = module.s3.keystore_bucket_name
}

output "artifacts_bucket_name" {
  description = "S3 bucket for CodePipeline artifacts"
  value       = module.s3.artifacts_bucket_name
}

# =============================================================================
# IAM
# =============================================================================
output "codebuild_role_arn" {
  description = "IAM role ARN for CodeBuild"
  value       = module.iam.codebuild_role_arn
}

output "codepipeline_role_arn" {
  description = "IAM role ARN for CodePipeline"
  value       = module.iam.codepipeline_role_arn
}

# =============================================================================
# CodeBuild
# =============================================================================
output "codebuild_android_project" {
  description = "CodeBuild Android project name"
  value       = module.codebuild.android_project_name
}

output "codebuild_ios_project" {
  description = "CodeBuild iOS project name"
  value       = module.codebuild.ios_project_name
}

# =============================================================================
# CodePipeline
# =============================================================================
output "pipeline_name" {
  description = "CodePipeline name"
  value       = module.codepipeline.pipeline_name
}

output "codestar_connection_arn" {
  description = "CodeStar connection ARN (must be confirmed in AWS Console)"
  value       = aws_codestarconnections_connection.github.arn
}

# =============================================================================
# Firebase
# =============================================================================
output "firebase_android_app_id" {
  description = "Firebase Android App ID"
  value       = module.firebase.firebase_android_app_id
}

output "firebase_ios_app_id" {
  description = "Firebase iOS App ID"
  value       = module.firebase.firebase_ios_app_id
}

# =============================================================================
# Feature flags
#
# All null unless feature_flags_backend = "aws".
# =============================================================================

output "flags_document_url" {
  description = "URL the app reads flags from. Build it into the app as FLAGS_URL (see fastlane/env.<env>)."
  value       = try(module.feature_flags[0].document_url, null)
}

output "flags_bucket_name" {
  description = "Bucket `make flags-publish` writes the document to"
  value       = try(module.feature_flags[0].bucket_name, null)
}

output "flags_distribution_id" {
  description = "CloudFront distribution invalidated after a publish"
  value       = try(module.feature_flags[0].distribution_id, null)
}

output "feature_flags_backend" {
  description = "Which flag backend this environment is configured for. scripts/flags.sh reads it to decide where to publish."
  value       = var.feature_flags_backend
}
