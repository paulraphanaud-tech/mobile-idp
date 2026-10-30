output "bucket_name" {
  description = "Name of the feature flag bucket"
  value       = aws_s3_bucket.flags.id
}

output "bucket_arn" {
  description = "ARN of the feature flag bucket"
  value       = aws_s3_bucket.flags.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID. `make flags-publish` invalidates the document path on it."
  value       = aws_cloudfront_distribution.flags.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN, for scoping the CreateInvalidation grant"
  value       = aws_cloudfront_distribution.flags.arn
}

output "domain_name" {
  description = "CloudFront domain serving the flag document"
  value       = aws_cloudfront_distribution.flags.domain_name
}

output "document_key" {
  description = "S3 key of this environment's published document"
  value       = local.document_key
}

output "document_url" {
  description = "The URL the app reads. Pass it to AwsFlagSource as FLAGS_URL."
  value       = "https://${aws_cloudfront_distribution.flags.domain_name}/${local.document_key}"
}
