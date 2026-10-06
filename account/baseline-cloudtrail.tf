# Account baseline: the CloudTrail trail and its log bucket, built in the console
# on 2026-10 and imported here (DEV-134). Every argument mirrors the live
# configuration; the import blocks can be removed after the first apply.
#
# No account ID literal anywhere: the bucket name and trail ARN are built from
# data sources. The data source names are specific to this file so they cannot
# collide with other baseline files.

data "aws_caller_identity" "baseline_trail" {}
data "aws_partition" "baseline_trail" {}
data "aws_region" "baseline_trail" {}

locals {
  trail_name       = "account-trail"
  trail_bucket     = "aws-cloudtrail-logs-${data.aws_caller_identity.baseline_trail.account_id}-046c8de7"
  trail_bucket_arn = "arn:${data.aws_partition.baseline_trail.partition}:s3:::${local.trail_bucket}"
  trail_arn        = "arn:${data.aws_partition.baseline_trail.partition}:cloudtrail:${data.aws_region.baseline_trail.region}:${data.aws_caller_identity.baseline_trail.account_id}:trail/${local.trail_name}"
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = local.trail_bucket
}

import {
  to = aws_s3_bucket.cloudtrail_logs
  id = local.trail_bucket
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

import {
  to = aws_s3_bucket_public_access_block.cloudtrail_logs
  id = local.trail_bucket
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

import {
  to = aws_s3_bucket_ownership_controls.cloudtrail_logs
  id = local.trail_bucket
}

# Live: SSE-S3 (AES256), bucket key off, SSE-C blocked.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    bucket_key_enabled = false

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    blocked_encryption_types = ["SSE-C"]
  }
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.cloudtrail_logs
  id = local.trail_bucket
}

# The two statements CloudTrail's console wizard created, Sids included.
data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    sid       = "AWSCloudTrailAclCheck20150319-0fe17a82-620f-4bc4-88cc-c4bdd99a4a62"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [local.trail_bucket_arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite20150319-d33f0aad-50e0-4693-8b65-9ebce39c748f"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${local.trail_bucket_arn}/AWSLogs/${data.aws_caller_identity.baseline_trail.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

import {
  to = aws_s3_bucket_policy.cloudtrail_logs
  id = local.trail_bucket
}

# Live: multi-region, global service events, log file validation, management
# events only (advanced selector), no CloudWatch Logs, SNS or KMS.
resource "aws_cloudtrail" "account" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true

  advanced_event_selector {
    name = "Management events selector"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

import {
  to = aws_cloudtrail.account
  id = local.trail_name
}
