# This directory IS "staging" -- the environment name is a literal here, not a
# variable, so there's no way to typo `-var="env=..."` on the command line
# and accidentally publish to (or read from) the wrong environment's SSM path.
locals {
  env = "staging"
}

module "vpc" {
  source = "git::https://gitlab.com/demo-org/terraform-modules.git//vpc?ref=v2.1.1"

  name_prefix          = var.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# This layer's public interface -- other layers in this same environment
# read these, never this layer's state file directly.
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/${local.env}/network/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/${local.env}/network/public_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.public_subnet_ids)
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/${local.env}/network/private_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.private_subnet_ids)
}
