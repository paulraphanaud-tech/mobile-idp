output "role_arn" {
  description = "Set this as the AWS_ROLE_ARN variable of the GitHub environment."
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "The GitHub OIDC provider used by the role."
  value       = local.provider_arn
}

output "allowed_subjects" {
  description = "OIDC subjects the role trusts."
  value       = local.allowed_subjects
}
