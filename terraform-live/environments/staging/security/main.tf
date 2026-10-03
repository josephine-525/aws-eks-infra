locals {
  env = "staging"
}

# db is a separate state -- read its published output via SSM, don't reach
# into its state file directly. Depends on this environment's OWN db output,
# never another environment's.
data "aws_ssm_parameter" "db_table_arn" {
  name = "/${local.env}/db/table_arn"
}

module "security" {
  source = "git::https://gitlab.com/demo-org/terraform-modules.git//security?ref=v1.0.0"

  name_prefix        = var.name_prefix
  dynamodb_table_arn = nonsensitive(data.aws_ssm_parameter.db_table_arn.value)
}

resource "aws_ssm_parameter" "eks_cluster_role_arn" {
  name  = "/${local.env}/security/eks_cluster_role_arn"
  type  = "String"
  value = module.security.eks_cluster_role_arn
}

resource "aws_ssm_parameter" "eks_node_role_arn" {
  name  = "/${local.env}/security/eks_node_role_arn"
  type  = "String"
  value = module.security.eks_node_role_arn
}

resource "aws_ssm_parameter" "eks_expense_backend_ddb_policy_arn" {
  name  = "/${local.env}/security/eks_expense_backend_ddb_policy_arn"
  type  = "String"
  value = module.security.eks_expense_backend_ddb_policy_arn
}

resource "aws_ssm_parameter" "aws_lbc_policy_arn" {
  name  = "/${local.env}/security/aws_lbc_policy_arn"
  type  = "String"
  value = module.security.aws_lbc_policy_arn
}
