output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = module.eks.cluster_version
}

output "node_security_group_id" {
  description = "Security group of the worker nodes (P2 databases allow ingress from it)."
  value       = module.eks.node_security_group_id
}

output "admin_role_arn" {
  description = "Role ARN granted cluster admin through an access entry."
  value       = local.admin_role_arn
}
