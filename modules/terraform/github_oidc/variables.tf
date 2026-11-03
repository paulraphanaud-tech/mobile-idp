variable "project_name" {
  description = "Prefix for the IAM role name (the infra's name_prefix)."
  type        = string
}

variable "repositories" {
  description = "GitHub repositories allowed to assume the role, as owner/repo."
  type        = list(string)
}

variable "github_environments" {
  description = <<-EOT
    GitHub environment names a job must declare (`environment: <name>`) to
    assume the role. Defaults to the IDP environment this stack describes, so
    the dev stack's role is only usable from jobs in the GitHub "dev"
    environment. Add required reviewers to that GitHub environment to put a
    human in front of every deploy.
  EOT
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. False if it already exists."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com provider (when create_oidc_provider = false)."
  type        = string
  default     = ""
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the role may read (the fastlane config and credentials paths)."
  type        = list(string)
}

variable "match_bucket_arn" {
  description = "ARN of the match certificates bucket (read-only access). null when match uses git storage."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for created resources."
  type        = map(string)
  default     = {}
}
