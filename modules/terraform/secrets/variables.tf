variable "project_name" {
  description = "Name of the project, used for tagging"
  type        = string
}

variable "secret_definitions" {
  description = "Map of secret paths to their definitions. The key becomes the secret name in Secrets Manager."
  type = map(object({
    description = string
  }))
}

variable "tags" {
  description = "Additional tags to apply to all secrets"
  type        = map(string)
  default     = {}
}
