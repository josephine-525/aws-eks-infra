locals {
  env = "dev"
}

module "db" {
  source = "git::https://gitlab.com/demo-org/terraform-modules.git//db?ref=v1.0.0"

  name_prefix = var.name_prefix
}

resource "aws_ssm_parameter" "table_name" {
  name  = "/${local.env}/db/table_name"
  type  = "String"
  value = module.db.table_name
}

resource "aws_ssm_parameter" "table_arn" {
  name  = "/${local.env}/db/table_arn"
  type  = "String"
  value = module.db.table_arn
}
