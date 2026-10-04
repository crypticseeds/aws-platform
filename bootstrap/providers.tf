provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-platform"
      Application = "platform"
      ManagedBy   = "terraform"
      Environment = "shared"
      Scope       = "shared" # used by every project in the account, not only aws-platform
      Root        = "bootstrap"
      Repository  = "github.com/crypticseeds/aws-platform"
    }
  }
}
