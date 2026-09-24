variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "name_prefix" {
  type = string
}

variable "eks_kubernetes_version" {
  type = string
}

variable "eks_node_instance_types" {
  type = list(string)
}

variable "eks_node_desired_size" {
  type = number
}

variable "eks_node_min_size" {
  type = number
}

variable "eks_node_max_size" {
  type = number
}

variable "eks_admin_principal_arn" {
  type    = string
  default = ""
}

variable "eks_ci_principal_arn" {
  type    = string
  default = ""
}
