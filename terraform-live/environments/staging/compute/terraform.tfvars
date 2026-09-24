# staging = placeholder sizing only, never applied. Bigger than dev's single node
# per group, still smaller than prod's.
name_prefix             = "demoapp-staging"
eks_kubernetes_version  = "1.35"
eks_node_instance_types = ["t3.large"]
eks_node_desired_size   = 2
eks_node_min_size       = 1
eks_node_max_size       = 3
