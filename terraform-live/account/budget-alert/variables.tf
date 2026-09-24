variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "name_prefix" {
  type    = string
  default = "demoapp-account"
}

variable "budget_alert_email" {
  type    = string
  default = ""
}

variable "budget_monthly_usd" {
  type = number
}

variable "enable_aws_budget" {
  type    = bool
  default = false
}
