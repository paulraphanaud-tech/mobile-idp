project_name         = "{{PROJECT_NAME}}"
environment          = "prod"
aws_region           = "{{AWS_REGION}}"
gcp_project_id       = "{{GCP_PROJECT_ID}}"
gcp_region           = "{{GCP_REGION}}"
android_package_name = "{{ANDROID_PACKAGE_NAME}}"
ios_bundle_id        = "{{IOS_BUNDLE_ID}}"
apple_team_id        = "{{APPLE_TEAM_ID}}"
repository_url       = "{{REPOSITORY_URL}}"
github_repo          = "{{GITHUB_REPO}}"
branch               = "main"
enable_approval      = true

# Two environments in ONE AWS account need distinct resource names — S3 bucket
# names are globally unique and IAM role names are account-unique. Set this to
# true at creation time for such a setup; see the variable's description in
# infra/variables.tf before flipping it on an existing deployment.
include_environment_in_resource_names = false

tags = {
  Environment = "prod"
  Team        = "mobile"
}
