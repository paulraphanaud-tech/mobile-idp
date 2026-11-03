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

# Skipped when android_package_name is empty (iOS-only projects).
resource "google_firebase_android_app" "this" {
  count = var.android_package_name == "" ? 0 : 1

  provider     = google-beta
  project      = var.gcp_project_id
  display_name = var.android_display_name != "" ? var.android_display_name : var.android_package_name
  package_name = var.android_package_name

  depends_on = [google_firebase_project.this]
}

################################################################################
# Firebase iOS (Apple) App
################################################################################

# Skipped when ios_bundle_id is empty (Android-only projects).
resource "google_firebase_apple_app" "this" {
  count = var.ios_bundle_id == "" ? 0 : 1

  provider     = google-beta
  project      = var.gcp_project_id
  display_name = var.ios_display_name != "" ? var.ios_display_name : var.ios_bundle_id
  bundle_id    = var.ios_bundle_id
  team_id      = var.apple_team_id == "" ? null : var.apple_team_id

  depends_on = [google_firebase_project.this]
}

################################################################################
# State moves for projects created before the apps became optional
#
# Without these, adding `count` above would plan a destroy + create of both
# Firebase apps in every existing project (new App IDs, broken distribution).
################################################################################

moved {
  from = google_firebase_android_app.this
  to   = google_firebase_android_app.this[0]
}

moved {
  from = google_firebase_apple_app.this
  to   = google_firebase_apple_app.this[0]
}
