################################################################################
# Enable Firebase on the GCP project
################################################################################

resource "google_firebase_project" "this" {
  provider = google-beta
  project  = var.gcp_project_id
}

################################################################################
# Firebase Android App
################################################################################

resource "google_firebase_android_app" "this" {
  provider     = google-beta
  project      = var.gcp_project_id
  display_name = var.android_display_name != "" ? var.android_display_name : var.android_package_name
  package_name = var.android_package_name

  depends_on = [google_firebase_project.this]
}

################################################################################
# Firebase iOS (Apple) App
################################################################################

resource "google_firebase_apple_app" "this" {
  provider     = google-beta
  project      = var.gcp_project_id
  display_name = var.ios_display_name != "" ? var.ios_display_name : var.ios_bundle_id
  bundle_id    = var.ios_bundle_id
  team_id      = var.apple_team_id

  depends_on = [google_firebase_project.this]
}
