data "aws_partition" "current" {}

# Identity Center creates one role per permission set, under the path
# /aws-reserved/sso.amazonaws.com/<region>/ and with a random suffix. Access
# entries take the role's real ARN, path included (only the legacy aws-auth
# ConfigMap needed the path stripped). The role is looked up by name, so
# nothing account-specific is hard-coded. one() fails the plan if the lookup
# finds zero or several roles.
data "aws_iam_roles" "admin" {
  name_regex  = "^AWSReservedSSO_${var.admin_permission_set_name}_[0-9a-f]+$"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

# Same lookup for the agent's read-only permission set.
data "aws_iam_roles" "agent_readonly" {
  name_regex  = "^AWSReservedSSO_${var.agent_permission_set_name}_[0-9a-f]+$"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  admin_role_arn          = one(data.aws_iam_roles.admin.arns)
  agent_readonly_role_arn = one(data.aws_iam_roles.agent_readonly.arns)
}

# Accepted trivy findings (dev cluster, reviewed 2026-10-04):
# AWS-0039: EKS envelope-encrypts all Kubernetes API data by default on 1.28+
#           with an AWS-owned key; no customer-managed key for a disposable cluster.
# AWS-0040: public endpoint is required for the owner's kubectl and is limited
#           to endpoint_public_access_cidrs (0.0.0.0/0 rejected by validation).
# AWS-0104: nodes need unrestricted egress (via NAT) for image pulls and AWS APIs.
# trivy:ignore:AWS-0039
# trivy:ignore:AWS-0040
# trivy:ignore:AWS-0104
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Public API endpoint, limited to the owner's IP ranges. Nodes reach the API
  # privately.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  endpoint_private_access      = true

  # Access entries only (no aws-auth ConfigMap). Admin access is granted to
  # the PlatformAdmin SSO role explicitly, not to "whoever ran apply".
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    platform_admin = {
      principal_arn = local.admin_role_arn
      policy_associations = {
        cluster_admin = {
          policy_arn   = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

    # The agent (read-only). No access policy on purpose: the role only maps
    # to the Kubernetes group below, and everything it may do comes from the
    # agent-readonly ClusterRole in platform/agent-rbac/ (no Secrets, no
    # writes). With no RBAC bound, it can do nothing.
    agent_readonly = {
      principal_arn     = local.agent_readonly_role_arn
      kubernetes_groups = ["agent-readonly"]
    }
  }

  # Workload IAM uses EKS Pod Identity, so no per-cluster OIDC provider.
  enable_irsa = false

  # Secrets are encrypted at rest by EKS's default envelope encryption with an
  # AWS-owned key. No customer KMS key: it would cost $1/month and leave a key
  # pending deletion after every destroy.
  create_kms_key    = false
  encryption_config = null

  # Audit + authenticator logs: who did what to the cluster (including the
  # agent). 7-day retention keeps CloudWatch cost small.
  enabled_log_types                      = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  addons = {
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy     = {}
    coredns        = {}
    metrics-server = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  # Passed explicitly (not only via provider default_tags) so the node launch
  # template tags the EC2 instances and EBS volumes it creates; default_tags
  # never reach those. Needed for per-project cost tracking.
  tags = var.tags
}
