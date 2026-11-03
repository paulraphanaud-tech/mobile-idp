variable "project_name" {
  description = "Project name used as prefix for S3 bucket names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all S3 buckets"
  type        = map(string)
  default     = {}
}

variable "create_match_bucket" {
  description = <<-EOT
    Create the Fastlane Match bucket. True when Match uses S3 storage; false
    when it uses git, where the certificates live in a repository instead.

    Turning this off on an existing project plans the bucket's destruction.
    force_destroy = false makes that apply fail while the bucket still holds
    certificates, so migrate them first (`fastlane match migrate`) and empty
    the bucket deliberately.
  EOT
  type        = bool
  default     = true
}
