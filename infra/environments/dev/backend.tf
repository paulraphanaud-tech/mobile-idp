terraform {
  backend "s3" {
    bucket         = "fastlane-ci-cd-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "fastlane-ci-cd-terraform-lock"
  }
}
