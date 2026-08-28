# =============================================================================
# S3
# =============================================================================
output "match_bucket_name" {
  description = "S3 bucket for Fastlane Match certificates"
  value       = module.s3.match_bucket_name
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
