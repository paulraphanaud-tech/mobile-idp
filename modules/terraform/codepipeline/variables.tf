variable "project_name" {
  description = "Name of the project, used as prefix for resource naming"
  type        = string
}

variable "pipeline_role_arn" {
  description = "IAM role ARN that CodePipeline assumes to execute actions"
  type        = string
}

variable "artifacts_bucket" {
  description = "S3 bucket name used for pipeline artifact storage"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo' format"
  type        = string

  validation {
    condition     = can(regex("^[\\w.-]+/[\\w.-]+$", var.github_repo))
    error_message = "github_repo must be in 'owner/repo' format."
  }
}

variable "branch" {
  description = "Git branch to track for source changes"
  type        = string
  default     = "main"
}

variable "codebuild_android_project" {
  description = "Name of the CodeBuild project for Android builds"
  type        = string
}

variable "codebuild_ios_project" {
  description = "Name of the CodeBuild project for iOS builds"
  type        = string
}

variable "enable_approval" {
  description = "Whether to add a manual approval stage before deployment"
  type        = bool
  default     = false
}

variable "approval_sns_topic_arn" {
  description = "SNS topic ARN for approval notifications (optional, used only when enable_approval is true)"
  type        = string
  default     = ""
}

variable "codestar_connection_arn" {
  description = "ARN of the CodeStar connection for GitHub"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}
