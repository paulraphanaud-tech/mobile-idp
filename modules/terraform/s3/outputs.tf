output "match_bucket_name" {
  description = "Name of the Fastlane Match S3 bucket"
  value       = aws_s3_bucket.match.id
}

output "match_bucket_arn" {
  description = "ARN of the Fastlane Match S3 bucket"
  value       = aws_s3_bucket.match.arn
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
