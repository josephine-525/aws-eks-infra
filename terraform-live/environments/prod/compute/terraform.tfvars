# prod = placeholder sizing only, never applied. Deliberately the biggest of
# the three, to communicate scale in the tfvars diff -- not a sized capacity
# plan.
name_prefix             = "demoapp-prod"
eks_kubernetes_version  = "1.35"
eks_node_instance_types = ["m5.xlarge"]
eks_node_desired_size   = 3
eks_node_min_size       = 2
eks_node_max_size       = 6
