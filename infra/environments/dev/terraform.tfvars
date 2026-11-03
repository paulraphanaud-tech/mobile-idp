project_name         = "{{PROJECT_NAME}}"
environment          = "dev"
aws_region           = "{{AWS_REGION}}"
gcp_project_id       = "{{GCP_PROJECT_ID}}"
gcp_region           = "{{GCP_REGION}}"
android_package_name = "{{ANDROID_PACKAGE_NAME}}"
ios_bundle_id        = "{{IOS_BUNDLE_ID}}"
apple_team_id        = "{{APPLE_TEAM_ID}}"
repository_url       = "{{REPOSITORY_URL}}"
github_repo          = "{{GITHUB_REPO}}"
branch               = "main"
enable_approval      = false

# Two environments in ONE AWS account need distinct resource names — S3 bucket
# names are globally unique and IAM role names are account-unique. Set this to
# true at creation time for such a setup; see the variable's description in
# infra/variables.tf before flipping it on an existing deployment.
include_environment_in_resource_names = false

# Where the app reads feature flags from.
#
#   "none"      No flag infrastructure; the app uses the defaults compiled in
#               from flags/flags.yaml.
#   "aws"       An S3 bucket behind CloudFront serving the document rendered
#               from flags.yaml. No credentials in the app; targeting and
#               percentage rollouts are evaluated on device.
#   "firebase"  Firebase Remote Config. Provisions nothing here. Note that
#               Remote Config is per Firebase PROJECT, so environments sharing
#               one project share one set of flag values.
#
# Switching later is a re-publish plus changing which FlagSource the app
# constructs — both backends read the same flags.yaml.
feature_flags_backend = "{{FEATURE_FLAGS_BACKEND}}"

tags = {
  Environment = "dev"
  Team        = "mobile"
}

# iOS signing — where Fastlane Match keeps the encrypted certificates.
#
#   "s3"   The per-project <prefix>-match bucket. Nothing else to configure.
#   "git"  A private repo. Set match_git_url, and match_git_auth to "https"
#          (base64 user:token) or "ssh" (deploy key); `make populate-secrets`
#          stores that credential. No match bucket is created.
#
# Keep fastlane/env.<env> (MATCH_STORAGE_MODE, MATCH_GIT_URL, MATCH_GIT_BRANCH)
# in agreement — it drives local runs, this drives CI.
match_storage_mode = "{{MATCH_STORAGE_MODE}}"
match_git_url      = "{{MATCH_GIT_URL}}"
match_git_branch   = "{{MATCH_GIT_BRANCH}}"
match_git_auth     = "{{MATCH_GIT_AUTH}}"
