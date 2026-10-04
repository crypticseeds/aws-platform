output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.network.vpc_id
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.cluster.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = module.cluster.cluster_version
}

output "configure_kubectl" {
  description = "Command to add this cluster to your kubeconfig."
  value       = "aws eks update-kubeconfig --name ${module.cluster.cluster_name} --region ${var.region} --profile platform-admin"
}
