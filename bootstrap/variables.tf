variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_prefix" {
  description = "Prefix for the account-wide state bucket name, shared by every project (each uses its own key). AWS appends a unique suffix. Must contain \"tfstate\" so the agent's read deny on state objects applies."
  type        = string
  default     = "aws-platform-tfstate-"

  validation {
    condition     = strcontains(var.state_bucket_prefix, "tfstate") && length(var.state_bucket_prefix) <= 37
    error_message = "The prefix must contain \"tfstate\" and be at most 37 characters (S3 bucket_prefix limit)."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old versions of state files before S3 deletes them."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 7
    error_message = "Keep old state versions for at least 7 days so a bad apply can be rolled back."
  }
}
