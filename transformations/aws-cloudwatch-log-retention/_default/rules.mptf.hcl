# GENERIC enforcement: CloudWatch Log Group retention (CIS AWS Foundations 3.4 —
# ensure CloudWatch log groups have a retention period set).
#
# Applies to ANY module declaring an aws_cloudwatch_log_group. The typed query
# matches by resource_type, so an empty result (module has no such resource) is
# a no-op. Forces a 1-year minimum so logs are not left set to never-expire,
# regardless of the caller's var values — this forces a 365-day retention.

data "resource" cloudwatch_log_group {
  resource_type = "aws_cloudwatch_log_group"
}

transform "update_in_place" cloudwatch_log_retention {
  for_each             = try(data.resource.cloudwatch_log_group.result.aws_cloudwatch_log_group, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    retention_in_days = 365
  }
}
