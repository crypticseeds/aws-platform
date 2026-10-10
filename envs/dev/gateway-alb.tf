# Security group for the gateway's internet-facing ALB (DEV-164). Without it
# the AWS Load Balancer Controller creates its own group open to 0.0.0.0/0,
# which would publish /metrics, /docs and the health details to the internet.
#
# The Ingress (charts/sre-inference-gateway/templates/ingress.yaml) attaches
# this group by its Name tag, so only the name lives in the public repo. The
# allowed CIDRs are the owner's, from the same git-ignored variable as the
# Kubernetes API allow-list.
#
# With a custom group the controller still adds the rules that let the ALB
# reach the pods (manage-backend-security-group-rules). Destroy the Ingress
# (Argo apps) before this group, as docs/runbooks/teardown.md already orders.

locals {
  gateway_alb_name = "${var.name}-gateway-alb"
}

resource "aws_security_group" "gateway_alb" {
  # checkov:skip=CKV2_AWS_5:Attached outside Terraform by the AWS Load Balancer Controller (Ingress annotation alb.ingress.kubernetes.io/security-groups).
  name = local.gateway_alb_name
  # Only a-zA-Z0-9, space and ._-:/()#,@[]+=&;{}!$* are allowed; AWS rejects anything else at apply time.
  description = "Gateway ALB: HTTP from the owner IP only."
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTP from the owner"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.endpoint_public_access_cidrs
  }

  # Targets are pod IPs inside the VPC (target-type ip).
  egress {
    description = "To pods and health checks inside the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  # The Ingress finds the group by this tag.
  tags = {
    Name = local.gateway_alb_name
  }
}
