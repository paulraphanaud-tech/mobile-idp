variable "project_name" {
  description = "Project name used as prefix for IAM resource names"
  type        = string
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs that CodeBuild is allowed to access"
  type        = list(string)
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs that CodeBuild is allowed to read"
  type        = list(string)
}

variable "codestar_connection_arn" {
  description = "ARN of the CodeStar connection used by CodePipeline for source actions"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all IAM resources"
  type        = map(string)
  default     = {}
}
