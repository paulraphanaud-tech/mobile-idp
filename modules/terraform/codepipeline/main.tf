################################################################################
# CodePipeline
################################################################################

resource "aws_codepipeline" "this" {
  name     = "${var.project_name}-pipeline"
  role_arn = var.pipeline_role_arn

  artifact_store {
    location = var.artifacts_bucket
    type     = "S3"
  }

  # ---------- Stage: Source ----------
  stage {
    name = "Source"

    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = var.github_repo
        BranchName       = var.branch
      }
    }
  }

  # ---------- Stage: Build_Android ----------
  stage {
    name = "Build_Android"

    action {
      name            = "Build_Android"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = var.codebuild_android_project
      }
    }
  }

  # ---------- Stage: Build_iOS ----------
  stage {
    name = "Build_iOS"

    action {
      name            = "Build_iOS"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = var.codebuild_ios_project
      }
    }
  }

  # ---------- Stage: Approval (optional) ----------
  dynamic "stage" {
    for_each = var.enable_approval ? [1] : []

    content {
      name = "Approval"

      action {
        name     = "Manual_Approval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = var.approval_sns_topic_arn != "" ? {
          NotificationArn = var.approval_sns_topic_arn
        } : {}
      }
    }
  }

  tags = var.tags
}
