provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-platform"
      Application = "platform"
      ManagedBy   = "terraform"
      Environment = "shared"
      Scope       = "shared" # account-wide singletons, survive envs/dev destroys
      Root        = "account"
      Repository  = "github.com/crypticseeds/aws-platform"
    }
  }
}
