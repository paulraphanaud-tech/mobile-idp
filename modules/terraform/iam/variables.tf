variable "project_name" {
  description = "Project name used as prefix for IAM resource names"
  type        = string
}

variable "s3_bucket_arns" {
  description = <<-EOT
    S3 bucket ARNs the **CodeBuild** role may read and write: the match
    bucket, the keystore bucket, and the artifacts bucket it pulls its input
    artifact from.

    This is deliberately not what the CodePipeline role gets — see
    artifacts_bucket_arn.
  EOT
  type        = list(string)
}

variable "artifacts_bucket_arn" {
  description = <<-EOT
    ARN of the CodePipeline artifacts bucket, and the only bucket the
    **CodePipeline** role gets write and delete access to.

    Passed separately from s3_bucket_arns on purpose: CodePipeline's job is
    moving artifacts between stages. It never reads a signing certificate or
    an Android keystore — only the CodeBuild jobs it starts do — so granting
    it s3:DeleteObject on those buckets was authority with no corresponding
    use.
  EOT
  type        = string
}

variable "codeartifact_domain_arn" {
  description = <<-EOT
    Optional. ARN of a CodeArtifact domain to allow CodeBuild to fetch an auth
    token for, e.g. "arn:aws:codeartifact:eu-west-1:123456789012:domain/my-domain".

    Empty by default, which emits no CodeArtifact permissions at all. This
    platform pulls gems from rubygems.org and Dart packages from pub.dev, so
    nothing needs CodeArtifact unless you have deliberately put a private
    registry in front of them.
  EOT
  type        = string
  default     = ""
}

variable "codeartifact_repository_arns" {
  description = <<-EOT
    Optional. ARNs of the CodeArtifact repositories CodeBuild may read from,
    e.g. ["arn:aws:codeartifact:eu-west-1:123456789012:repository/my-domain/ruby"].

    Required alongside codeartifact_domain_arn — the domain ARN covers the
    auth token, the repository ARNs cover reading packages.
  EOT
  type        = list(string)
  default     = []
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
