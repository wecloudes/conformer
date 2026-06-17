# GENERIC enforcement: EFS encryption at rest (CIS AWS Foundations — encryption at rest).
#
# Applies to ANY module declaring an aws_efs_file_system. The typed query matches
# by resource_type, so an empty result (module has no such resource) is a no-op.
# Forces encrypted = true regardless of the caller's var values.

data "resource" efs {
  resource_type = "aws_efs_file_system"
}

transform "update_in_place" efs_encrypt {
  for_each             = try(data.resource.efs.result.aws_efs_file_system, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    encrypted = true
  }
}
