################################################################################
# S3 Buckets for Flutter CI/CD IDP
#
# 1. Match bucket    – iOS Fastlane Match certificates & profiles
# 2. Keystore bucket – Android signing keystores
# 3. Artifacts bucket – CodePipeline build artifacts
################################################################################

# ---------- Match bucket (Fastlane Match) ------------------------------------
#
# Only when Match stores certificates in S3. With git storage the certificates
# live in a repository and this bucket would sit empty.

resource "aws_s3_bucket" "match" {
  count         = var.create_match_bucket ? 1 : 0
  bucket        = "${var.project_name}-match"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${var.project_name}-match"
    Purpose = "fastlane-match"
  })
}

resource "aws_s3_bucket_versioning" "match" {
  count  = var.create_match_bucket ? 1 : 0
  bucket = aws_s3_bucket.match[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "match" {
  count  = var.create_match_bucket ? 1 : 0
  bucket = aws_s3_bucket.match[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "match" {
  count  = var.create_match_bucket ? 1 : 0
  bucket = aws_s3_bucket.match[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# These resources had no count before git storage was supported. The moved
# blocks keep existing projects' bucket at its old state address, so upgrading
# the module plans no replacement of signing material.
moved {
  from = aws_s3_bucket.match
  to   = aws_s3_bucket.match[0]
}

moved {
  from = aws_s3_bucket_versioning.match
  to   = aws_s3_bucket_versioning.match[0]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.match
  to   = aws_s3_bucket_server_side_encryption_configuration.match[0]
}

moved {
  from = aws_s3_bucket_public_access_block.match
  to   = aws_s3_bucket_public_access_block.match[0]
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
