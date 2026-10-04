terraform {
  backend "s3" {
    bucket       = "aws-platform-tfstate-e62514a9b973c8e95b9ebccad0"
    key          = "aws-platform/dev/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }
}
