variable "region" {
  description = "AWS region for this root's provider. IAM is global; this only sets where API calls go."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Name of the account-wide Terraform state bucket (bootstrap output state_bucket_name). The CI plan role may read state in it and write only .tflock objects."
  type        = string
  default     = "aws-platform-tfstate-e62514a9b973c8e95b9ebccad0"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose pull request workflows may assume the CI plan role."
  type        = string
  default     = "crypticseeds/aws-platform"
}
