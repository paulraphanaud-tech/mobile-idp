output "secret_arns" {
  description = "List of all secret ARNs"
  value       = [for secret in aws_secretsmanager_secret.this : secret.arn]
}

output "secret_names" {
  description = "Map of definition key to secret name"
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}

output "secret_arns_map" {
  description = "Map of definition key to secret ARN"
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}
