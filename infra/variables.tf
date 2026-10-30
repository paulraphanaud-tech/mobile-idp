# =============================================================================
# General
# =============================================================================
variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod). Selects the Secrets Manager path prefix, and — when include_environment_in_resource_names is true — is part of every resource name."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with hyphens, max 16 chars (it becomes part of S3 bucket and IAM role names)."
  }
}

variable "include_environment_in_resource_names" {
  description = <<-EOT
    Whether AWS resource names include the environment: `<project>-<env>-match`
    instead of `<project>-match`.

    Defaults to false, which is the historical behaviour and means two
    environments in the same AWS account COLLIDE — S3 bucket names are globally
    unique and IAM role names are account-unique, so the second `terraform
    apply` fails on duplicates.

    Set it to true for any project that runs more than one environment in a
    single AWS account. Do this at creation time: flipping it on an existing
    deployment renames every resource, which Terraform implements as
    destroy-and-recreate. The match and keystore buckets have
    force_destroy = false, so that apply errors out half-way rather than
    deleting signing material — recoverable, but a bad afternoon.

    Leave it false if each environment gets its own AWS account (the stronger
    isolation boundary, where identical names are fine).
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# AWS
# =============================================================================
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

# =============================================================================
# GCP / Firebase
# =============================================================================
variable "gcp_project_id" {
  description = "Google Cloud project ID for Firebase"
  type        = string
}

variable "gcp_region" {
  description = "Google Cloud region"
  type        = string
  default     = "europe-west1"
}

variable "android_package_name" {
  description = "Android package name (e.g. fr.ippon.fastlane_ci_cd)"
  type        = string
}

variable "ios_bundle_id" {
  description = "iOS bundle identifier (e.g. fr.ippon.fastlane-ci-cd)"
  type        = string
}

variable "apple_team_id" {
  description = "Apple Developer Team ID"
  type        = string
}

# =============================================================================
# CI/CD
# =============================================================================
variable "repository_url" {
  description = "GitHub repository URL for CodeBuild source"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format"
  type        = string
}

variable "branch" {
  description = "Git branch to build"
  type        = string
  default     = "main"
}

variable "enable_approval" {
  description = "Enable manual approval stage in CodePipeline"
  type        = bool
  default     = false
}

# =============================================================================
# Observability
# =============================================================================
variable "metrics_namespace" {
  description = <<-EOT
    CloudWatch namespace for the build metrics emitted by
    scripts/build-metrics.sh (BuildDurationSeconds, LeadTimeSeconds).

    Set to "" to disable: CodeBuild then gets no cloudwatch:PutMetricData
    permission and the scripts skip publishing. Timings are still printed to
    the build log either way.
  EOT
  type        = string
  default     = "MobileIDP"
}

# =============================================================================
# Secrets
# =============================================================================
variable "secret_definitions" {
  description = <<-EOT
    Override for the Secrets Manager paths to create.

    Leave empty (the default) to use the per-environment paths derived from
    var.environment in main.tf: `<env>/fastlane/config`,
    `<env>/fastlane/credentials`, `<env>/android/signing`,
    `<env>/android/play_store`.

    Only set this if you need paths that do not follow that scheme — and if
    you do, `secret_path()` in scripts/setup.sh must be changed to match, or
    `make populate-secrets` writes to paths CodeBuild is not reading.
  EOT
  type        = map(object({ description = string }))
  default     = {}
}
