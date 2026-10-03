# prod = placeholder sizing only, deliberately bigger than dev/staging. This
# environment is never applied -- the point is that the directory/state/
# module-call shape is real and complete.
name_prefix = "demoapp-prod"
vpc_cidr    = "10.70.0.0/16"

public_subnet_cidrs  = ["10.70.0.0/20", "10.70.16.0/20", "10.70.32.0/20"]
private_subnet_cidrs = ["10.70.128.0/20", "10.70.144.0/20", "10.70.160.0/20"]
