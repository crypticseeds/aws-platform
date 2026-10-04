locals {
  # Standard tags for every project (see the tagging ADR). Also passed to the
  # modules so resources outside default_tags' reach (node instances and
  # volumes) carry them. Everything in this root is shared platform; app-owned
  # AWS resources live in apps/<app>/<env> with Application=<app>.
  tags = {
    Project     = "aws-platform"
    Application = "platform"
    Environment = "dev"
    ManagedBy   = "terraform"
    Repository  = "github.com/crypticseeds/aws-platform"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
