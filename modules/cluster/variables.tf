variable "name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version, e.g. \"1.36\"."
  type        = string
}

variable "vpc_id" {
  description = "VPC to run the cluster in."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the nodes and control plane ENIs."
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR ranges allowed to reach the public Kubernetes API endpoint (the owner's IPs). No default on purpose."
  type        = list(string)

  # Every entry must be a single IPv4 address (/32). Rejecting only 0.0.0.0/0 is
  # not enough: two /1 ranges would also open the endpoint to the whole internet.
  validation {
    condition = length(var.endpoint_public_access_cidrs) > 0 && alltrue([
      for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0)) && endswith(c, "/32") && !strcontains(c, ":")
    ])
    error_message = "Give at least one CIDR, each a single IPv4 address as /32, e.g. [\"203.0.113.10/32\"]."
  }
}

variable "admin_permission_set_name" {
  description = "Identity Center permission set whose role gets cluster admin."
  type        = string
  default     = "PlatformAdmin"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired number of nodes at creation."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags for every resource, including nodes and their volumes (launch template)."
  type        = map(string)
  default     = {}
}
