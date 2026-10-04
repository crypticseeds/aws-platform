# 0003. Community `terraform-aws-modules` for the VPC and EKS

- Status: accepted
- Date: 2026-10-04

## Context

The dev platform needs a VPC and an EKS cluster. Both are well-trodden, and writing them from raw resources would take a lot of time for little learning beyond what the modules already encode. The risk with modules is that they create resources the reader never sees in this repo.

## Decision

Wrap the community modules in thin local modules, pinned to exact versions:

- `modules/network` wraps [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) **6.7.3**.
- `modules/cluster` wraps [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) **21.26.0**.

Each wrapper sets only the inputs this project cares about. The lists below record what each module creates without it appearing in our code, read from the module source at the pinned version.

### What the VPC module hides

- The subnets themselves: one private /20 and one public /24 per AZ, from the CIDR maths in `modules/network/main.tf`.
- An internet gateway, plus a public route table with a `0.0.0.0/0` route to it and its subnet associations.
- The NAT gateway and its Elastic IP. With `single_nat_gateway = true` the module creates **one** private route table, shared by all private subnets, with its default route through that NAT ([0004](0004-single-nat-gateway.md)).
- It adopts the VPC's **default security group, default network ACL and default route table** (`manage_default_* = true` by default). The default security group is managed with no rules, so anything accidentally placed in it gets no traffic.

### What the EKS module hides

- **Cluster IAM role**, with `AmazonEKSClusterPolicy` attached.
- **Node IAM role** for the managed node group, with `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly` and `AmazonEKS_CNI_Policy`. Because IRSA is off, the VPC CNI uses the node role's CNI permissions ([0009](0009-eks-security-choices.md)).
- **Security groups**: an additional cluster security group, and a node security group with rules for kubelet from the control plane, CoreDNS between nodes, node-to-node ephemeral ports, and all egress. EKS also creates its own primary cluster security group.
- **Access entries and policy associations**, from the `access_entries` map (the `PlatformAdmin` entry).
- **Add-ons**: `vpc-cni` and `eks-pod-identity-agent` before nodes join, then `kube-proxy` and `coredns`.
- **A launch template** for the node group. This is how `var.tags` reach the EC2 instances and EBS volumes ([0008](0008-tagging-and-layering.md)).
- **The control-plane CloudWatch log group**, with the 7-day retention we pass.

Things the module *can* create but which are switched off here: the IRSA OIDC provider (`enable_irsa = false`) and the KMS key (`create_kms_key = false`).

## Consequences

- Far less code to review, and the module's defaults reflect common practice.
- Upgrades must be deliberate: exact version pins, each upgrade in its own PR, and a plan read for replacements.
- Debugging sometimes means reading module source. The source was read at the pinned version to confirm that `encryption_config = null` disables the CMK, that `enable_irsa = false` skips the OIDC provider, and that the launch template merges `var.tags` (journal 03).

## Alternatives

- **Raw resources for both.** Most educational, slowest, and easy to get subtly wrong (route tables, security group rules, node bootstrap).
- **A raw VPC with the EKS module.** The VPC is the simpler of the two to hand-write, but it still saves little time. The "what it hides" list gives most of the learning value without the cost.
