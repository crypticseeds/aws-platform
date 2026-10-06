# Console-built account defaults, imported (DEV-134). Each import block makes the
# first plan a no-op. Import blocks are idempotent: once the resource is in state
# they are ignored, so they can stay.

# Own caller-identity lookup (not the conventional name "current") so this file
# cannot collide with a data source of the same name added elsewhere in this root.
data "aws_caller_identity" "account_defaults" {}

# Account-level S3 Block Public Access. Complements the per-bucket blocks.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

import {
  to = aws_s3_account_public_access_block.this
  id = data.aws_caller_identity.account_defaults.account_id
}

# EBS encryption by default for the provider region. The default KMS key is the
# AWS-managed alias/aws/ebs, so no aws_ebs_default_kms_key resource is needed.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

import {
  to = aws_ebs_encryption_by_default.this
  id = "default"
}
