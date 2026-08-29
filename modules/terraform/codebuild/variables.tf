variable "project_name" {
  description = "Name of the project, used as prefix for CodeBuild project names"
  type        = string
}

variable "repository_url" {
  description = "GitHub repository URL for the source code"
  type        = string
}

variable "branch" {
  description = "Git branch to build"
  type        = string
  default     = "main"
}

variable "codebuild_role_arn" {
  description = "IAM role ARN for CodeBuild to assume"
  type        = string
}

variable "android_buildspec" {
  description = "Path to the Android buildspec file"
  type        = string
  default     = "buildspec.yaml"
}

variable "ios_buildspec" {
  description = "Path to the iOS buildspec file"
  type        = string
  default     = "buildspec_ios.yml"
}

variable "environment_variables" {
  description = "Map of plaintext environment variables (name -> value) for both projects"
  type        = map(string)
  default     = {}
}

variable "secrets_manager_variables" {
  description = "Map of Secrets Manager environment variables (name -> secret reference) for both projects"
  type        = map(string)
  default     = {}
}

variable "android_compute_type" {
  description = "Compute type for the Android CodeBuild project. MEDIUM (3GB RAM) is not enough for a real Flutter/Gradle/NDK build — the Gradle daemon gets OOM-killed partway through assembleRelease."
  type        = string
  default     = "BUILD_GENERAL1_LARGE"
}

variable "ios_compute_type" {
  description = "Compute type for the iOS CodeBuild project (Mac fleet). BUILD_GENERAL1_LARGE is not available in all regions for MAC_ARM."
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
}

variable "tags" {
  description = "Additional tags to apply to all CodeBuild projects"
  type        = map(string)
  default     = {}
}
