project_name         = "{{PROJECT_NAME}}"
environment          = "staging"
aws_region           = "{{AWS_REGION}}"
gcp_project_id       = "{{GCP_PROJECT_ID}}"
gcp_region           = "{{GCP_REGION}}"
android_package_name = "{{ANDROID_PACKAGE_NAME}}"
ios_bundle_id        = "{{IOS_BUNDLE_ID}}"
apple_team_id        = "{{APPLE_TEAM_ID}}"
repository_url       = "{{REPOSITORY_URL}}"
github_repo          = "{{GITHUB_REPO}}"
branch               = "staging"
enable_approval      = true

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
  Environment = "staging"
  Team        = "mobile"
}
