output "codebuild_role_arn" {
  description = "ARN of the CodeBuild service IAM role"
  value       = aws_iam_role.codebuild.arn
}

output "codebuild_role_name" {
  description = "Name of the CodeBuild service IAM role"
  value       = aws_iam_role.codebuild.name
}

output "codepipeline_role_arn" {
  description = "ARN of the CodePipeline service IAM role"
  value       = aws_iam_role.codepipeline.arn
}

output "codepipeline_role_name" {
  description = "Name of the CodePipeline service IAM role"
  value       = aws_iam_role.codepipeline.name
}
