output "state_bucket_name" {
  description = "Name of the Terraform state bucket. Goes into each root's backend block."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  description = "Region of the state bucket."
  value       = var.region
}
