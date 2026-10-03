# dev = the real spec: 3 node groups, 1 node each, 3 nodes total.
name_prefix             = "demoapp-dev"
eks_kubernetes_version  = "1.35"
eks_node_instance_types = ["t3.large"] # bumped from t3.medium 2026-10-01 -- same 2 vCPUs, double the memory
# (4GB -> 8GB). Needed once Kafka moved from 1 broker to 3
# (one per AZ, for real HA) -- Kafka's JVM is memory-hungry,
# and this fleet already shares these 3 nodes with ArgoCD/
# kube-prometheus-stack/3 team namespaces, so vCPU headroom
# wasn't the binding constraint, memory was.
eks_node_desired_size = 1
eks_node_min_size     = 1
eks_node_max_size     = 2

# eks_admin_principal_arn is intentionally NOT set here -- same reason the
# original project set it via a GitLab CI variable (EKS_ADMIN_PRINCIPAL_ARN)
# instead of committing it: it's a real IAM ARN with this account's ID in it,
# and this file gets committed to git. Set it via TF_VAR_eks_admin_principal_arn
# in your shell before running terraform (see command below), not here.
