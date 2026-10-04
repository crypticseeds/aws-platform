# network

Dev-grade VPC for an EKS cluster, wrapping [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) 6.7.3.

- One private /20 per AZ for nodes and pods (the VPC CNI gives every pod a VPC IP).
- One public /24 per AZ for the ALB and the NAT gateway.
- A single NAT gateway shared by all AZs (cheaper, but not AZ-redundant).
- Load Balancer Controller discovery tags on both subnet tiers.
- A free S3 gateway endpoint on the private route tables.

## Inputs

| Name | Type | Description |
|---|---|---|
| `name` | string | Name prefix for the VPC and its resources. |
| `vpc_cidr_block` | string | A /16 CIDR block. |
| `azs` | list(string) | 2 or 3 availability zones. |
| `tags` | map(string) | Extra tags on every resource. |

## Outputs

`vpc_id`, `private_subnet_ids`, `public_subnet_ids`.
