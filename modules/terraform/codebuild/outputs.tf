output "android_project_name" {
  description = "Name of the Android CodeBuild project"
  value       = aws_codebuild_project.android.name
}

output "android_project_arn" {
  description = "ARN of the Android CodeBuild project"
  value       = aws_codebuild_project.android.arn
}

output "ios_project_name" {
  description = "Name of the iOS CodeBuild project"
  value       = aws_codebuild_project.ios.name
}

output "ios_project_arn" {
  description = "ARN of the iOS CodeBuild project"
  value       = aws_codebuild_project.ios.arn
}
