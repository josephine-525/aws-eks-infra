module "ecr" {
  source = "git::https://gitlab.com/demo-org/terraform-modules.git//ecr?ref=v1.0.0"

  name_prefix = var.name_prefix
}

# Published for CI (or any environment's deploy step) to read directly --
# not consumed by any other Terraform layer in this design, since compute
# gets image refs from CI at deploy time, not through Terraform.
resource "aws_ssm_parameter" "backend_repository_url" {
  name  = "/account/ecr/backend_repository_url"
  type  = "String"
  value = module.ecr.backend_repository_url
}

resource "aws_ssm_parameter" "frontend_repository_url" {
  name  = "/account/ecr/frontend_repository_url"
  type  = "String"
  value = module.ecr.frontend_repository_url
}
