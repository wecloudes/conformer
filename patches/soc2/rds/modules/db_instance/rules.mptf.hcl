# HARD enforcement for terraform-aws-rds.
#
# The real aws_db_instance lives in the module's local submodule
# modules/db_instance/. patch-module.sh runs mapotf HERE (in that subdir, because
# this rules file mirrors the path <module>/modules/db_instance/), so the
# override lands on the actual resource — the caller's var values are replaced
# and cannot weaken the control. This is the hard counterpart to the soft root
# variable-default overrides in _default/aws-modules.mptf.hcl.

data "resource" rds {
  resource_type = "aws_db_instance"
}

transform "update_in_place" rds_harden {
  for_each             = try(data.resource.rds.result.aws_db_instance, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    storage_encrypted                   = true
    deletion_protection                 = true
    publicly_accessible                 = false
    iam_database_authentication_enabled = true
    performance_insights_enabled        = true
  }
}
