terraform {
  backend "s3" {
    bucket         = "{{PROJECT_NAME}}-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "{{AWS_REGION}}"
    encrypt        = true
    dynamodb_table = "{{PROJECT_NAME}}-terraform-lock"
  }
}
