terraform {
  backend "s3" {
    bucket         = "demoapp-terraform-state"
    key            = "terraform-live/dev/compute/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "demoapp-terraform-locks"
    encrypt        = true
  }
}
