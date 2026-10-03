provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "demoapp"
      Scope     = "account"
      Layer     = "budget-alert"
      ManagedBy = "terraform"
    }
  }
}
