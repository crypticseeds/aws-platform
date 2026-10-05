locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
}

# One per issuer URL per account, shared by every project's CI role (ADR 0010).
# No thumbprint_list: AWS verifies GitHub's certificate against its own trusted
# root CAs. The argument is optional and computed in the pinned provider, so
# leaving it out causes no drift.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# Plan-only CI role (ADR 0007). Only pull request workflows of this repo can
# assume it; pushes to main and other refs cannot.
data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    sid     = "GitHubPullRequests"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "ci_plan" {
  name                 = "aws-platform-ci-plan"
  description          = "GitHub Actions terraform plan for pull requests. Read-only, plus state lock objects."
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ci_plan_read_only" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# What a plan needs on the state bucket beyond ReadOnlyAccess: read state, and
# create and remove the S3-native lock file (ADR 0005). Nothing else is writable.
data "aws_iam_policy_document" "ci_plan_state" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/*"]
  }

  statement {
    sid       = "WriteLockFilesOnly"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "ci_plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_plan_state.json
}
