variable "region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "eu-west-2"
}

variable "name" {
  description = "Name used for the VPC and the EKS cluster."
  type        = string
  default     = "aws-platform-dev"
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block (/16)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use (2 or 3)."
  type        = number
  default     = 3
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. 1.36 is the EKS default on 2026-10-04, in standard support until 2027-08."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 instance type for the worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API, e.g. [\"203.0.113.10/32\"] for the owner's public IP. Set in terraform.tfvars (git-ignored)."
  type        = list(string)
  # The owner's IP: keep it out of plan output, which CI posts to public PR comments and logs.
  sensitive = true
}

variable "cost_alert_emails" {
  description = "Email addresses notified when this project's spend in the month passes $30 and $50 (budget.tf), e.g. [\"you@example.com\"]. Personal data in a public repo, so no default: set it in terraform.tfvars (git-ignored); CI takes it from the TF_VAR_COST_ALERT_EMAILS secret."
  type        = list(string)
  # Keep the addresses out of plan output, which CI posts to public PR comments and logs.
  sensitive = true

  validation {
    condition     = length(var.cost_alert_emails) > 0 && alltrue([for e in var.cost_alert_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+$", e))])
    error_message = "cost_alert_emails needs at least one email address."
  }
}
