# cluster

EKS cluster with one managed node group, wrapping [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) 21.26.0.

- Access entries only (`authentication_mode = "API"`). Cluster admin goes to the Identity Center `PlatformAdmin` role, found by name; no account ID in code.
- Public API endpoint restricted to the given CIDRs; private endpoint on.
- EKS Pod Identity for workload IAM (no IRSA OIDC provider).
- Kubernetes API data encrypted by EKS's default envelope encryption (AWS-owned key). No customer-managed KMS key: this is a disposable dev cluster.
- Audit and authenticator control-plane logs, 7-day retention.
- Core add-ons: vpc-cni and eks-pod-identity-agent (before nodes), kube-proxy, coredns, metrics-server (for `kubectl top`).
- AL2023 nodes, IMDSv2 required (module default). `tags` reach the node launch template, so instances and volumes are tagged for cost tracking.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | | Cluster name. |
| `kubernetes_version` | string | | e.g. `"1.36"`. |
| `vpc_id` | string | | VPC ID. |
| `subnet_ids` | list(string) | | Private subnet IDs. |
| `endpoint_public_access_cidrs` | list(string) | | Owner IPs allowed to reach the API. `0.0.0.0/0` is rejected. |
| `admin_permission_set_name` | string | `PlatformAdmin` | Permission set that gets cluster admin. |
| `node_instance_type` | string | `t3.medium` | Node instance type. |
| `node_min_size` / `node_max_size` / `node_desired_size` | number | 2 / 3 / 2 | Node group size. |
| `tags` | map(string) | `{}` | Tags for every resource, including nodes. |

## Outputs

`cluster_name`, `cluster_endpoint`, `cluster_version`, `node_security_group_id`, `admin_role_arn`.
