output "match_bucket_name" {
  description = "Name of the Fastlane Match S3 bucket. null when create_match_bucket = false."
  value       = try(aws_s3_bucket.match[0].id, null)
}

output "match_bucket_arn" {
  description = "ARN of the Fastlane Match S3 bucket. null when create_match_bucket = false."
  value       = try(aws_s3_bucket.match[0].arn, null)
}

output "keystore_bucket_name" {
  description = "Name of the Android keystore S3 bucket"
  value       = aws_s3_bucket.keystore.id
}

output "keystore_bucket_arn" {
  description = "ARN of the Android keystore S3 bucket"
  value       = aws_s3_bucket.keystore.arn
}

output "artifacts_bucket_name" {
  description = "Name of the CodePipeline artifacts S3 bucket"
  value       = aws_s3_bucket.artifacts.id
}

output "artifacts_bucket_arn" {
  description = "ARN of the CodePipeline artifacts S3 bucket"
  value       = aws_s3_bucket.artifacts.arn
}
