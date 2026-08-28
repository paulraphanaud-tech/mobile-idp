variable "gcp_project_id" {
  description = "GCP project ID where Firebase will be enabled"
  type        = string
}

variable "android_package_name" {
  description = "Android application package name (e.g. com.example.app)"
  type        = string
}

variable "ios_bundle_id" {
  description = "iOS application bundle identifier (e.g. com.example.app)"
  type        = string
}

variable "android_display_name" {
  description = "Display name for the Android app in Firebase console. Defaults to android_package_name if empty."
  type        = string
  default     = ""
}

variable "ios_display_name" {
  description = "Display name for the iOS app in Firebase console. Defaults to ios_bundle_id if empty."
  type        = string
  default     = ""
}

variable "apple_team_id" {
  description = "Apple Developer Team ID associated with the iOS app"
  type        = string
}
