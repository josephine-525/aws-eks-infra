provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "demoapp"
      Environment = "dev"
      Layer       = "security"
      ManagedBy   = "terraform"
    }
  }
}
