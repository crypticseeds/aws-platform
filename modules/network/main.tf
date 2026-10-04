module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr_block
  azs  = var.azs

  # /20 private subnets for nodes and pods (VPC CNI gives pods VPC IPs),
  # /24 public subnets for the ALB and the NAT gateway.
  private_subnets = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr_block, 4, i)]
  public_subnets  = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr_block, 8, 48 + i)]

  # One NAT gateway shared by all AZs: cheaper, but one AZ outage cuts egress
  # for the others. See the NAT ADR.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet discovery tags for the AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = var.tags
}

data "aws_region" "current" {}

# Free gateway endpoint: S3 traffic from private subnets (including image
# layers served from S3) stays on the AWS network instead of paying NAT data
# processing charges.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}
