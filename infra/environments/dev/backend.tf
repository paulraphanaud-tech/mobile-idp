# Partial backend configuration, consumed by:
#   terraform init -backend-config=environments/dev/backend.tf
#
# This file must contain bare key = value pairs. A full `terraform { backend
# "s3" {} }` block is NOT valid here — terraform init rejects it with
# "Invalid backend configuration argument". The block itself lives in
# infra/versions.tf; this only fills in its arguments.
bucket         = "{{PROJECT_NAME}}-terraform-state"
key            = "dev/terraform.tfstate"
region         = "{{AWS_REGION}}"
encrypt        = true
dynamodb_table = "{{PROJECT_NAME}}-terraform-lock"
