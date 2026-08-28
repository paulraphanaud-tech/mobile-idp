################################################################################
# S3 Buckets for Flutter CI/CD IDP
#
# 1. Match bucket    – iOS Fastlane Match certificates & profiles
# 2. Keystore bucket – Android signing keystores
# 3. Artifacts bucket – CodePipeline build artifacts
################################################################################

# ---------- Match bucket (Fastlane Match) ------------------------------------

resource "aws_s3_bucket" "match" {
  bucket        = "${var.project_name}-match"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${var.project_name}-match"
    Purpose = "fastlane-match"
  })
}

resource "aws_s3_bucket_versioning" "match" {
  bucket = aws_s3_bucket.match.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "match" {
  bucket = aws_s3_bucket.match.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "match" {
  bucket = aws_s3_bucket.match.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- Keystore bucket (Android) ----------------------------------------

resource "aws_s3_bucket" "keystore" {
  bucket        = "${var.project_name}-keystores"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${var.project_name}-keystores"
    Purpose = "android-keystores"
  })
}

resource "aws_s3_bucket_versioning" "keystore" {
  bucket = aws_s3_bucket.keystore.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "keystore" {
  bucket = aws_s3_bucket.keystore.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "keystore" {
  bucket = aws_s3_bucket.keystore.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- Artifacts bucket (CodePipeline) -----------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${var.project_name}-artifacts"
    Purpose = "codepipeline-artifacts"
  })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
