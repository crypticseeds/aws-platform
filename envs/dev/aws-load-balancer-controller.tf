# IAM for the AWS Load Balancer Controller, linked to its service account
# through EKS Pod Identity (ADR 0009). The controller itself is installed by
# Argo CD (argocd/apps/aws-load-balancer-controller.yaml); the namespace and
# service account name here must match that Application's values.

locals {
  lb_controller_namespace       = "kube-system"
  lb_controller_service_account = "aws-load-balancer-controller"
}

data "aws_iam_policy_document" "lb_controller_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.name}-aws-load-balancer-controller"
  description        = "AWS Load Balancer Controller in ${var.name}, via EKS Pod Identity."
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust.json
}

# Upstream policy for controller v3.5.0, vendored unchanged from
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json
# Replace the file (and its name) whenever the chart's controller version
# changes; the policy is versioned with the controller.
resource "aws_iam_policy" "lb_controller" {
  name        = "${var.name}-aws-load-balancer-controller"
  description = "Upstream AWS Load Balancer Controller v3.5.0 policy."
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v3.5.0.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = module.cluster.cluster_name
  namespace       = local.lb_controller_namespace
  service_account = local.lb_controller_service_account
  role_arn        = aws_iam_role.lb_controller.arn
}
