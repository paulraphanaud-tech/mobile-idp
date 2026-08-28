# =============================================================================
# General
# =============================================================================
variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
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
# Secrets
# =============================================================================
variable "secret_definitions" {
  description = "Map of secret paths to create in AWS Secrets Manager"
  type        = map(object({ description = string }))
  default = {
    "dev/secret/fastlane" = {
      description = "Fastlane app config (FLAVOR, SCHEME, Firebase App IDs)"
    }
    "secret/env/fastlane" = {
      description = "Fastlane credentials (Firebase CLI token, ASC keys)"
    }
    "prod/android/signing" = {
      description = "Android keystore signing credentials"
    }
    "prod/android/play_store" = {
      description = "Google Play service account JSON key"
    }
  }
}
