# Catalog unit — CIS-hardened terraform-aws-modules/vpc from the registry.
# Same pattern as s3-bucket: only the `source` differs from pulling upstream.
# The vpc units add prevent_destroy + ignore_changes=[tags] on every resource
# and force VPC flow logs (traffic_type = ALL) at build time.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr://${include.root.locals.framework_host}/terraform-aws-modules/vpc/aws?version=5.13.0"
}

inputs = {
  name = "compliant-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # The aws-vpc-flow-logs unit forces traffic_type = "ALL"; enable the flow log
  # so the control has something to harden.
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
}
