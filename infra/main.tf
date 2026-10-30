# =============================================================================
# Naming and secret paths
# =============================================================================
locals {
  # Every AWS resource is named "<name_prefix>-<thing>". With
  # include_environment_in_resource_names = false (the default) the prefix is
  # just the project, which is why two environments cannot coexist in one AWS
  # account — see the variable's description.
  name_prefix = var.include_environment_in_resource_names ? "${var.project_name}-${var.environment}" : var.project_name

  # Secrets Manager paths, per environment. Changing this scheme means also
  # changing secret_path() in scripts/setup.sh — populate-secrets and CodeBuild
  # must agree, or builds fail at startup resolving a path nobody wrote to.
  secret_paths = {
    fastlane_config = "${var.environment}/fastlane/config"
    fastlane_creds  = "${var.environment}/fastlane/credentials"
    android_signing = "${var.environment}/android/signing"
    play_store      = "${var.environment}/android/play_store"
  }

  default_secret_definitions = {
    (local.secret_paths.fastlane_config) = {
      description = "Fastlane app config for ${var.environment} (FLAVOR, SCHEME, Firebase App IDs). Identifiers, not credentials."
    }
    (local.secret_paths.fastlane_creds) = {
      description = "Fastlane credentials for ${var.environment} (Firebase CLI token, App Store Connect API key, MATCH_PASSWORD)."
    }
    (local.secret_paths.android_signing) = {
      description = "Android keystore signing credentials for ${var.environment}."
    }
    (local.secret_paths.play_store) = {
      description = "Google Play service account JSON key for ${var.environment}."
    }
  }

  secret_definitions = length(var.secret_definitions) > 0 ? var.secret_definitions : local.default_secret_definitions
}

# =============================================================================
# CodeStar Connection (GitHub) - created at root to avoid circular deps
#
# Connection names are capped at 32 characters, which the project name plus an
# environment suffix can exceed — terraform apply reports it clearly if so.
# =============================================================================
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name_prefix}-github"
  provider_type = "GitHub"

  tags = var.tags
}

# =============================================================================
# S3 Buckets (Match, Keystores, Artifacts)
# =============================================================================
module "s3" {
  source       = "../modules/terraform/s3"
  project_name = local.name_prefix
  tags         = var.tags
}

# =============================================================================
# Secrets Manager
# =============================================================================
module "secrets" {
  source = "../modules/terraform/secrets"
  # Tag-only use, so this stays the real project name rather than the prefix.
  project_name       = var.project_name
  secret_definitions = local.secret_definitions
  tags               = merge(var.tags, { Environment = var.environment })
}

# =============================================================================
# IAM Roles (CodeBuild + CodePipeline)
# =============================================================================
module "iam" {
  source = "../modules/terraform/iam"

  project_name = local.name_prefix

  s3_bucket_arns = [
    module.s3.match_bucket_arn,
    module.s3.keystore_bucket_arn,
    module.s3.artifacts_bucket_arn,
  ]

  secrets_arns            = module.secrets.secret_arns
  codestar_connection_arn = aws_codestarconnections_connection.github.arn

  tags = var.tags
}

# =============================================================================
# CodeBuild Projects (Android + iOS)
# =============================================================================
module "codebuild" {
  source = "../modules/terraform/codebuild"

  project_name       = local.name_prefix
  repository_url     = var.repository_url
  branch             = var.branch
  codebuild_role_arn = module.iam.codebuild_role_arn

  environment_variables = {
    FASTLANE_ENV    = var.environment
    MATCH_S3_BUCKET = module.s3.match_bucket_name
    # Two names for one bucket: buildspec.yaml reads S3_BUCKET_NAME, while
    # modules/fastlane/keystore reads S3_KEYSTORE_BUCKET. Setting both means
    # `make upload-keystore` works in CI as well as the build's own download.
    S3_BUCKET_NAME     = module.s3.keystore_bucket_name
    S3_KEYSTORE_BUCKET = module.s3.keystore_bucket_name
  }

  # This block, not the buildspec, is where secrets are wired in. A buildspec's
  # `secrets-manager:` section is a static mapping with no variable expansion,
  # so it cannot express "<env>/fastlane/config" — one repo has one buildspec
  # but several environments. Injecting here keeps the paths env-aware.
  #
  # Left-hand names are what fastlane actually reads (see templates/fastlane/
  # Fastfile and modules/fastlane/*). They are not free-form: the App Store
  # Connect ones must be spelled APP_STORE_CONNECT_API_KEY_* for
  # app_store_connect_api_key to pick them up.
  secrets_manager_variables = {
    FLAVOR                              = "${local.secret_paths.fastlane_config}:FLAVOR"
    SCHEME                              = "${local.secret_paths.fastlane_config}:SCHEME"
    FIREBASE_APP_ANDROID                = "${local.secret_paths.fastlane_config}:FIREBASE_APP_ANDROID"
    FIREBASE_APP_IOS                    = "${local.secret_paths.fastlane_config}:FIREBASE_APP_IOS"
    APP_STORE_TESTER_GROUP              = "${local.secret_paths.fastlane_config}:APP_STORE_TESTER_GROUP"
    FL_AWS_REGION                       = "${local.secret_paths.fastlane_config}:AWS_REGION"
    FIREBASE_CLI_TOKEN                  = "${local.secret_paths.fastlane_creds}:FIREBASE_CLI_TOKEN"
    APP_STORE_CONNECT_API_KEY_KEY_ID    = "${local.secret_paths.fastlane_creds}:APP_STORE_CONNECT_KEY_ID"
    APP_STORE_CONNECT_API_KEY_ISSUER_ID = "${local.secret_paths.fastlane_creds}:APP_STORE_CONNECT_ISSUER_ID"
    APP_STORE_CONNECT_API_KEY_KEY       = "${local.secret_paths.fastlane_creds}:APP_STORE_CONNECT_KEY_CONTENT"
    MATCH_PASSWORD                      = "${local.secret_paths.fastlane_creds}:MATCH_PASSWORD"
    KEYSTORE_PASSWORD                   = "${local.secret_paths.android_signing}:KEYSTORE_PASSWORD"
    KEY_ALIAS                           = "${local.secret_paths.android_signing}:KEY_ALIAS"
    KEY_PASSWORD                        = "${local.secret_paths.android_signing}:KEY_PASSWORD"
  }

  tags = var.tags
}

# =============================================================================
# CodePipeline
# =============================================================================
module "codepipeline" {
  source = "../modules/terraform/codepipeline"

  project_name              = local.name_prefix
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
