module "budget_alert" {
  source = "git::https://gitlab.com/demo-org/terraform-modules.git//budget-alert?ref=v1.0.0"

  name_prefix        = var.name_prefix
  budget_alert_email = var.budget_alert_email
  budget_monthly_usd = var.budget_monthly_usd
  enable_aws_budget  = var.enable_aws_budget
}
