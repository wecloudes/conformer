# GENERIC enforcement: CloudTrail integrity + coverage
# (CIS AWS Foundations 3.1 / 3.2 / 3.5).
#
# Applies to ANY module declaring an aws_cloudtrail. The typed query matches by
# resource_type, so an empty result (module has no such resource) is a no-op.
# Forces log file validation, multi-region coverage, and global service events
# regardless of the caller's var values.

data "resource" cloudtrail {
  resource_type = "aws_cloudtrail"
}

transform "update_in_place" cloudtrail_harden {
  for_each             = try(data.resource.cloudtrail.result.aws_cloudtrail, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    enable_log_file_validation    = true
    is_multi_region_trail         = true
    include_global_service_events = true
  }
}
