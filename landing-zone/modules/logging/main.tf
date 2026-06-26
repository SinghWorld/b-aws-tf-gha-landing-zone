locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "personal-landing-zone"
    },
    var.tags
  )

  # S3 key prefixes for CloudTrail and Config deliveries. Declared once here
  # and referenced from both the resource config AND the bucket policy so the
  # two never drift apart - drift here silently breaks log delivery with an
  # opaque InsufficientS3BucketPolicyException at apply time.
  cloudtrail_prefix = "cloudtrail"
  config_prefix     = "config"
}

# AWS-managed CMK used by the bucket's SSE-KMS encryption. The Config delivery
# channel requires this ARN explicitly when the destination bucket uses
# SSE-KMS - it cannot infer it from the bucket (see AWS docs:
# https://docs.aws.amazon.com/config/latest/developerguide/s3-kms-key.html).
data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

# ---------- Centralized log bucket (Log Archive account equivalent) ----------
resource "aws_s3_bucket" "log_archive" {
  bucket = var.log_bucket_name

  tags = merge(local.common_tags, {
    Name = var.log_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "log_archive" {
  bucket                  = aws_s3_bucket.log_archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms" # Uses AWS-managed aws/s3 CMK; Config delivery can work with this
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      object_size_greater_than = 0
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    expiration {
      days = var.log_retention_days
    }
  }
}

# Bucket policy: deny delete of objects, deny non-TLS - simulates Log Archive immutability
data "aws_iam_policy_document" "log_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.log_archive.arn]
    # NOTE: s3:x-amz-acl condition is NOT applied to GetBucketAcl because AWS
    # rejects it as incompatible with this action+resource combination. CloudTrail
    # writes objects with bucket-owner-full-control ACL via the PutObject statement
    # below, which is where the condition is enforced.
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.log_archive.arn}/${local.cloudtrail_prefix}/AWSLogs/${var.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "AWSConfigWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.log_archive.arn}/${local.config_prefix}/AWSLogs/${var.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "AWSConfigRead"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.log_archive.arn]
  }

  statement {
    sid    = "DenyObjectDeletion"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.log_archive.arn}/*"]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.log_archive.arn, "${aws_s3_bucket.log_archive.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id
  policy = data.aws_iam_policy_document.log_bucket_policy.json
}

# ---------- CloudTrail ----------
resource "aws_cloudtrail" "this" {
  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.log_archive.id
  s3_key_prefix                 = local.cloudtrail_prefix
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = local.common_tags

  depends_on = [aws_s3_bucket_policy.log_archive]
}

# ---------- AWS Config ----------
resource "aws_iam_role" "config_role" {
  name = "config-recorder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# NOTE: AWS allows only one bucket policy per S3 bucket. The Config write/read
# permissions are already declared in `data.aws_iam_policy_document.log_bucket_policy`
# (statements `AWSConfigWrite` and `AWSConfigRead`), so a single
# `aws_s3_bucket_policy` above is sufficient — no separate "addendum" needed.
resource "aws_config_configuration_recorder" "this" {
  name     = "personal-lab-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "personal-lab-delivery-channel"
  s3_bucket_name = aws_s3_bucket.log_archive.id
  s3_key_prefix  = local.config_prefix
  # Required when the destination bucket uses SSE-KMS. Without this, Config
  # returns InsufficientDeliveryPolicyException with "provided kms key is
  # 'null'". Using the AWS-managed aws/s3 alias here because the bucket's
  # SSE-KMS configuration also defaults to aws/s3 - keeping the two aligned
  # avoids any cross-key permission headaches.
  s3_kms_key_arn = data.aws_kms_alias.s3.arn

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
