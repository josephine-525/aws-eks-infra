provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "demoapp"
      Environment = "prod"
      Layer       = "security"
      ManagedBy   = "terraform"
    }
  }
}
