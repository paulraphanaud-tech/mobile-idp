variable "project_name" {
  description = "Project name used as prefix for S3 bucket names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all S3 buckets"
  type        = map(string)
  default     = {}
}
