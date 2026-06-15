# terraform-aws-modules (Anton Babenko) family pack.
#
# These modules are wrappers: the real resources live in local submodules
# (e.g. terraform-aws-rds → modules/db_instance/aws_db_instance.this). mapotf's
# data "resource" sees only the dir it runs in, so resource-level overrides do
# NOT reach those submodules. Instead we override the ROOT pass-through variable
# defaults, which the wrapper forwards to its submodules.
#
# This is SOFT (a caller can still pass a value) but works uniformly across the
# wrapper modules. For HARD enforcement on a specific module, add a
# module-specific rule that mapotf runs inside the submodule dir.
#
# All overrides are GUARDED by data.variable presence, so the file is a safe
# no-op on modules that lack a given variable. The data block is named `awv` to
# avoid colliding with `all` in avm.mptf.hcl (mapotf merges all *.mptf.hcl).

data "variable" awv {
}

locals {
  # secure value = true
  aws_force_true = [
    "storage_encrypted",                     # terraform-aws-rds (CIS RDS)
    "deletion_protection",                   # terraform-aws-rds
    "iam_database_authentication_enabled",   # terraform-aws-rds
    "performance_insights_enabled",          # terraform-aws-rds
    "enable_flow_log",                       # terraform-aws-vpc (CIS 3.9)
    "create_flow_log_cloudwatch_log_group",  # terraform-aws-vpc
  ]
  # secure value = false
  aws_force_false = [
    "publicly_accessible",                   # terraform-aws-rds
    "cluster_endpoint_public_access",        # terraform-aws-eks
  ]
  aws_true_present  = [for v in local.aws_force_true : v if contains(keys(try(data.variable.awv.result, {})), v)]
  aws_false_present = [for v in local.aws_force_false : v if contains(keys(try(data.variable.awv.result, {})), v)]
}

transform "update_in_place" aws_force_true {
  for_each             = try(toset(local.aws_true_present), [])
  target_block_address = "variable.${each.value}"
  asraw {
    default = true
  }
}

transform "update_in_place" aws_force_false {
  for_each             = try(toset(local.aws_false_present), [])
  target_block_address = "variable.${each.value}"
  asraw {
    default = false
  }
}
