# dev = the real spec that's actually applied: 1 VPC, 3 AZs.
name_prefix = "demoapp-dev"
vpc_cidr    = "10.50.0.0/16"

public_subnet_cidrs  = ["10.50.0.0/20", "10.50.16.0/20", "10.50.32.0/20"]
private_subnet_cidrs = ["10.50.128.0/20", "10.50.144.0/20", "10.50.160.0/20"]
