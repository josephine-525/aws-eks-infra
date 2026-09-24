# staging = placeholder sizing only. This environment is never applied -- the
# point is that the directory/state/module-call shape is real and complete.
name_prefix = "demoapp-staging"
vpc_cidr    = "10.60.0.0/16"

public_subnet_cidrs  = ["10.60.0.0/20", "10.60.16.0/20", "10.60.32.0/20"]
private_subnet_cidrs = ["10.60.128.0/20", "10.60.144.0/20", "10.60.160.0/20"]
