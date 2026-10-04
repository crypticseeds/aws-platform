data "aws_availability_zones" "available" {
  state = "available"
}

module "network" {
  source = "../../modules/network"

  name           = var.name
  vpc_cidr_block = var.vpc_cidr_block
  azs            = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  tags           = local.tags
}

module "cluster" {
  source = "../../modules/cluster"

  name                         = var.name
  kubernetes_version           = var.kubernetes_version
  vpc_id                       = module.network.vpc_id
  subnet_ids                   = module.network.private_subnet_ids
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  node_instance_type           = var.node_instance_type
  tags                         = local.tags
}
