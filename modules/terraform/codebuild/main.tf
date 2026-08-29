###############################################################################
# Android CodeBuild Project
###############################################################################

resource "aws_codebuild_project" "android" {
  name         = "${var.project_name}-android"
  description  = "Android build pipeline for ${var.project_name}"
  service_role = var.codebuild_role_arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = var.android_compute_type
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
        type  = "PLAINTEXT"
      }
    }

    dynamic "environment_variable" {
      for_each = var.secrets_manager_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
        type  = "SECRETS_MANAGER"
      }
    }
  }

  source {
    type            = "GITHUB"
    location        = var.repository_url
    buildspec       = var.android_buildspec
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  source_version = var.branch

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = "/codebuild/${var.project_name}-android"
    }
  }

  tags = merge(var.tags, {
    Project  = var.project_name
    Platform = "android"
  })
}

###############################################################################
# Mac Fleet (reserved capacity) — macOS CodeBuild environments are not
# available as on-demand compute; they require a Fleet.
###############################################################################

resource "aws_codebuild_fleet" "mac" {
  name             = "${var.project_name}-mac-fleet"
  base_capacity    = 1
  compute_type     = var.ios_compute_type
  environment_type = "MAC_ARM"

  tags = merge(var.tags, {
    Project  = var.project_name
    Platform = "ios"
  })
}

###############################################################################
# iOS CodeBuild Project
###############################################################################

resource "aws_codebuild_project" "ios" {
  name         = "${var.project_name}-ios"
  description  = "iOS build pipeline for ${var.project_name}"
  service_role = var.codebuild_role_arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = var.ios_compute_type
    image        = "aws/codebuild/macos-aarch64-sonoma:4.0"
    type         = "MAC_ARM"

    fleet {
      fleet_arn = aws_codebuild_fleet.mac.arn
    }

    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
        type  = "PLAINTEXT"
      }
    }

    dynamic "environment_variable" {
      for_each = var.secrets_manager_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
        type  = "SECRETS_MANAGER"
      }
    }
  }

  source {
    type            = "GITHUB"
    location        = var.repository_url
    buildspec       = var.ios_buildspec
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  source_version = var.branch

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = "/codebuild/${var.project_name}-ios"
    }
  }

  tags = merge(var.tags, {
    Project  = var.project_name
    Platform = "ios"
  })
}
