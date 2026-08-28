output "firebase_android_app_id" {
  description = "Firebase App ID for the Android application"
  value       = google_firebase_android_app.this.app_id
}

output "firebase_ios_app_id" {
  description = "Firebase App ID for the iOS application"
  value       = google_firebase_apple_app.this.app_id
}

output "gcp_project_number" {
  description = "GCP project number for the Firebase-enabled project"
  value       = google_firebase_project.this.project_number
}
