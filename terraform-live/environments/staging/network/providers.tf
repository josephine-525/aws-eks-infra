provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "demoapp"
      Environment = "staging"
      Layer       = "network"
      ManagedBy   = "terraform"
    }
  }
}
