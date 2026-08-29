# =============================================================================
# CodeStar Connection (GitHub) - created at root to avoid circular deps
# =============================================================================
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github"
  provider_type = "GitHub"

  tags = var.tags
}

# =============================================================================
# S3 Buckets (Match, Keystores, Artifacts)
# =============================================================================
module "s3" {
  source       = "../modules/terraform/s3"
  project_name = var.project_name
  tags         = var.tags
}

# =============================================================================
# Secrets Manager
# =============================================================================
module "secrets" {
  source             = "../modules/terraform/secrets"
  project_name       = var.project_name
  secret_definitions = var.secret_definitions
  tags               = var.tags
}

# =============================================================================
# IAM Roles (CodeBuild + CodePipeline)
# =============================================================================
module "iam" {
  source = "../modules/terraform/iam"

  project_name = var.project_name
  s3_bucket_arns = [
    module.s3.match_bucket_arn,
    module.s3.keystore_bucket_arn,
    module.s3.artifacts_bucket_arn,
  ]
  secrets_arns            = module.secrets.secret_arns
  codestar_connection_arn = aws_codestarconnections_connection.github.arn
  tags                    = var.tags
}

# =============================================================================
# CodeBuild Projects (Android + iOS)
# =============================================================================
module "codebuild" {
  source = "../modules/terraform/codebuild"

  project_name       = var.project_name
  repository_url     = var.repository_url
  branch             = var.branch
  codebuild_role_arn = module.iam.codebuild_role_arn

  environment_variables = {
    FASTLANE_ENV     = var.environment
    MATCH_S3_BUCKET  = module.s3.match_bucket_name
    S3_BUCKET_NAME   = module.s3.keystore_bucket_name
  }

  secrets_manager_variables = {
    FLAVOR                       = "dev/secret/fastlane:FLAVOR"
    SCHEME                       = "dev/secret/fastlane:SCHEME"
    FIREBASE_APP_ANDROID         = "dev/secret/fastlane:FIREBASE_APP_ANDROID"
    FIREBASE_APP_IOS             = "dev/secret/fastlane:FIREBASE_APP_IOS"
    APP_STORE_TESTER_GROUP       = "dev/secret/fastlane:APP_STORE_TESTER_GROUP"
    FL_AWS_REGION                = "dev/secret/fastlane:AWS_REGION"
    FIREBASE_CLI_TOKEN           = "secret/env/fastlane:FIREBASE_CLI_TOKEN"
    APP_STORE_CONNECT_KEY_ID     = "secret/env/fastlane:APP_STORE_CONNECT_KEY_ID"
    APP_STORE_CONNECT_ISSUER_ID  = "secret/env/fastlane:APP_STORE_CONNECT_ISSUER_ID"
    APP_STORE_CONNECT_KEY_CONTENT = "secret/env/fastlane:APP_STORE_CONNECT_KEY_CONTENT"
    MATCH_PASSWORD               = "secret/env/fastlane:MATCH_PASSWORD"
    KEYSTORE_B64                 = "prod/android/signing:KEYSTORE_BASE64"
    KEYSTORE_PASSWORD            = "prod/android/signing:KEYSTORE_PASSWORD"
    KEY_ALIAS                    = "prod/android/signing:KEY_ALIAS"
    KEY_PASSWORD                 = "prod/android/signing:KEY_PASSWORD"
  }

  tags = var.tags
}

# =============================================================================
# CodePipeline
# =============================================================================
module "codepipeline" {
  source = "../modules/terraform/codepipeline"

  project_name              = var.project_name
  pipeline_role_arn         = module.iam.codepipeline_role_arn
  artifacts_bucket          = module.s3.artifacts_bucket_name
  github_repo               = var.github_repo
  branch                    = var.branch
  codebuild_android_project = module.codebuild.android_project_name
  codebuild_ios_project     = module.codebuild.ios_project_name
  codestar_connection_arn   = aws_codestarconnections_connection.github.arn
  enable_approval           = var.enable_approval
  tags                      = var.tags
}

# =============================================================================
# Firebase (Google Cloud)
# =============================================================================
module "firebase" {
  source = "../modules/terraform/firebase"

  gcp_project_id       = var.gcp_project_id
  android_package_name = var.android_package_name
  ios_bundle_id        = var.ios_bundle_id
  apple_team_id        = var.apple_team_id
}
