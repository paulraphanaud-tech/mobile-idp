################################################################################
# Feature flag distribution
#
# Publishes the flag document generated from flags.yaml to S3 and serves it
# through CloudFront.
#
# Why this shape rather than AWS AppConfig, which is the service actually named
# "feature flags": AppConfig's data API is SigV4-signed, so reaching it from a
# phone means shipping a Cognito identity pool that mints AWS credentials for
# anyone who asks, and it bills per configuration request with no CDN in front.
# It is built for a fleet of servers, not millions of devices.
#
# A published JSON document behind CloudFront has neither problem: no AWS
# credentials in the app binary, edge-cached, effectively free at any install
# base. The staged rollout AppConfig would have contributed is provided instead
# by client-side targeting in the document itself, which is strictly more useful
# here because it addresses *users* rather than config propagation.
################################################################################

locals {
  bucket_name  = "${var.project_name}-flags"
  document_key = "${var.environment}/flags.json"
  origin_id    = "s3-${local.bucket_name}"
}

# ---------- Bucket ------------------------------------------------------------

resource "aws_s3_bucket" "flags" {
  bucket = local.bucket_name

  # Unlike the match and keystore buckets, nothing here is irreplaceable — the
  # document is regenerated from flags.yaml by `make flags-publish`. It is
  # still false so that `terraform destroy` does not quietly discard the
  # published state of every environment.
  force_destroy = false

  tags = merge(var.tags, {
    Name    = local.bucket_name
    Purpose = "feature-flags"
  })
}

# Versioning is the rollback mechanism: a bad publish is undone by restoring
# the previous object version, which is faster than regenerating from a
# reverted commit and does not need CI to be healthy.
resource "aws_s3_bucket_versioning" "flags" {
  bucket = aws_s3_bucket.flags.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flags" {
  bucket = aws_s3_bucket.flags.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The document is served publicly through CloudFront, but the bucket itself is
# not public: CloudFront reads it with origin access control and the bucket
# policy below names that distribution specifically.
resource "aws_s3_bucket_public_access_block" "flags" {
  bucket = aws_s3_bucket.flags.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- CloudFront --------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "flags" {
  name                              = "${var.project_name}-flags-oac"
  description                       = "Origin access control for the ${var.project_name} feature flag document"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# A dedicated cache policy rather than a managed one, because the managed
# policies either cache far too long for a kill switch or not at all.
resource "aws_cloudfront_cache_policy" "flags" {
  name        = "${var.project_name}-flags-cache"
  comment     = "Short-TTL policy for the feature flag document"
  default_ttl = var.cache_ttl_seconds
  max_ttl     = var.cache_ttl_seconds
  # Zero, so an invalidation from `make flags-publish` takes effect immediately
  # rather than being held by a minimum.
  min_ttl = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    # The document is identical for every caller — targeting is evaluated on
    # device. Forwarding anything would fragment the cache for no benefit.
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "flags" {
  enabled     = true
  comment     = "${var.project_name} feature flags"
  price_class = var.price_class

  origin {
    domain_name              = aws_s3_bucket.flags.bucket_regional_domain_name
    origin_id                = local.origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.flags.id
  }

  default_cache_behavior {
    target_origin_id = local.origin_id

    # Read-only by construction. A distribution that cannot accept a write is
    # one fewer thing to reason about when it is reachable from the internet.
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.flags.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # The default *.cloudfront.net certificate. A custom domain would need an
    # ACM certificate in us-east-1 and a DNS zone this platform does not
    # manage; the app reads the URL from configuration, so the hostname being
    # ugly costs nothing.
    cloudfront_default_certificate = true
  }

  tags = merge(var.tags, {
    Name    = "${var.project_name}-flags"
    Purpose = "feature-flags"
  })
}

# ---------- Bucket policy -----------------------------------------------------

data "aws_iam_policy_document" "flags_bucket" {
  # Only this distribution may read, and only this distribution. The SourceArn
  # condition is what stops another account's CloudFront distribution from
  # being pointed at this bucket.
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.flags.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.flags.arn]
    }
  }

  # Refuse plaintext access outright. Cheap to state, and it is the hardening
  # step the other buckets in this platform do not yet have.
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.flags.arn,
      "${aws_s3_bucket.flags.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flags" {
  bucket = aws_s3_bucket.flags.id
  policy = data.aws_iam_policy_document.flags_bucket.json

  # The public access block must exist first, or S3 can evaluate the new policy
  # against a bucket that is still accepting public policies.
  depends_on = [aws_s3_bucket_public_access_block.flags]
}
