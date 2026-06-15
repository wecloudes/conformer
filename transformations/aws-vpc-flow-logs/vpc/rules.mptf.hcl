# HARD enforcement for terraform-aws-vpc.
#
# aws_flow_log.this lives at the module root (flat module), so this rule runs at
# the root. The _default aws-modules pack already enables flow logs (soft); here
# we force the captured traffic to ALL (CIS 3.9 — reject-only logging is
# insufficient), regardless of var.flow_log_traffic_type.

data "resource" fl {
  resource_type = "aws_flow_log"
}

transform "update_in_place" flow_log_all {
  for_each             = try(data.resource.fl.result.aws_flow_log, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    traffic_type = "ALL"
  }
}
