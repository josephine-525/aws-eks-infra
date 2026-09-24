locals {
  env = "prod"
}

# network and security are separate states -- read their published output via
# SSM, don't reach into their state files directly. Both reads are scoped to
# THIS environment; compute must never read another environment's network or
# security output.
data "aws_ssm_parameter" "vpc_id" {
  name = "/${local.env}/network/vpc_id"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${local.env}/network/public_subnet_ids"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${local.env}/network/private_subnet_ids"
}

data "aws_ssm_parameter" "eks_cluster_role_arn" {
  name = "/${local.env}/security/eks_cluster_role_arn"
}

data "aws_ssm_parameter" "eks_node_role_arn" {
  name = "/${local.env}/security/eks_node_role_arn"
}

data "aws_ssm_parameter" "eks_expense_backend_ddb_policy_arn" {
  name = "/${local.env}/security/eks_expense_backend_ddb_policy_arn"
}

data "aws_ssm_parameter" "aws_lbc_policy_arn" {
  name = "/${local.env}/security/aws_lbc_policy_arn"
}

module "compute" {
  source = "git::https://gitlab.com/demo-org/terraform-modules.git//compute?ref=v1.0.0"

  enabled                            = true
  name_prefix                        = var.name_prefix
  aws_region                         = var.aws_region
  vpc_id                             = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  public_subnet_ids                  = nonsensitive(split(",", data.aws_ssm_parameter.public_subnet_ids.value))
  private_subnet_ids                 = nonsensitive(split(",", data.aws_ssm_parameter.private_subnet_ids.value))
  eks_kubernetes_version             = var.eks_kubernetes_version
  eks_node_instance_types            = var.eks_node_instance_types
  eks_node_desired_size              = var.eks_node_desired_size
  eks_node_min_size                  = var.eks_node_min_size
  eks_node_max_size                  = var.eks_node_max_size
  eks_cluster_role_arn               = nonsensitive(data.aws_ssm_parameter.eks_cluster_role_arn.value)
  eks_node_role_arn                  = nonsensitive(data.aws_ssm_parameter.eks_node_role_arn.value)
  eks_expense_backend_ddb_policy_arn = nonsensitive(data.aws_ssm_parameter.eks_expense_backend_ddb_policy_arn.value)
  aws_lbc_policy_arn                 = nonsensitive(data.aws_ssm_parameter.aws_lbc_policy_arn.value)
  eks_admin_principal_arn            = var.eks_admin_principal_arn
  eks_ci_principal_arn               = var.eks_ci_principal_arn
}

# Published so expenseapp's CI can read these at deploy time -- same purpose
# as the old runtime-eks-internal SSM params, just published at the call
# site now instead of inside the module.
resource "aws_ssm_parameter" "eks_expense_backend_role_arn" {
  name  = "/${local.env}/compute/eks_expense_backend_role_arn"
  type  = "String"
  value = module.compute.eks_expense_backend_irsa_role_arn
}

resource "aws_ssm_parameter" "aws_lbc_role_arn" {
  name  = "/${local.env}/compute/aws_lbc_role_arn"
  type  = "String"
  value = module.compute.aws_lbc_role_arn
}

resource "aws_ssm_parameter" "eks_alb_security_group_id" {
  name  = "/${local.env}/compute/eks_alb_security_group_id"
  type  = "String"
  value = module.compute.eks_alb_security_group_id
}
