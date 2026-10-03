# Account-scoped, not per-environment -- budget/cost alerting covers the
# whole AWS account, not any one environment, so it doesn't belong under
# environments/{dev,staging,prod}/. Its own independent state, its own key prefix.
terraform {
  backend "s3" {
    bucket         = "demoapp-terraform-state"
    key            = "terraform-live/account/budget-alert/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "demoapp-terraform-locks"
    encrypt        = true
  }
}
