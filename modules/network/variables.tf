variable "name" {
  description = "Name prefix for the VPC and its resources."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block. Must be a /16 so the subnet maths in main.tf fits."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && endswith(var.vpc_cidr_block, "/16")
    error_message = "cidr must be a valid /16 block, e.g. 10.20.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across (2 or 3)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "EKS needs at least 2 AZs; the subnet maths supports up to 3."
  }
}

variable "tags" {
  description = "Tags added to every resource the module creates (on top of provider default_tags)."
  type        = map(string)
  default     = {}
}
