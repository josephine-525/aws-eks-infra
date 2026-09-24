# dev = the real spec: 3 node groups, 1 node each, 3 nodes total.
name_prefix             = "demoapp-dev"
eks_kubernetes_version  = "1.35"
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size   = 1
eks_node_min_size       = 1
eks_node_max_size       = 2

# eks_admin_principal_arn is intentionally NOT set here -- same reason the
# original project set it via a GitLab CI variable (EKS_ADMIN_PRINCIPAL_ARN)
# instead of committing it: it's a real IAM ARN with this account's ID in it,
# and this file gets committed to git. Set it via TF_VAR_eks_admin_principal_arn
# in your shell before running terraform (see command below), not here.
