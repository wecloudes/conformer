# GENERIC enforcement: EBS encryption at rest (CIS AWS Foundations 2.2.1).
#
# Applies to ANY module declaring an aws_ebs_volume. The typed query matches by
# resource_type, so an empty result (module has no such resource) is a no-op.
# Forces encrypted = true regardless of the caller's var values.

data "resource" ebs {
  resource_type = "aws_ebs_volume"
}

transform "update_in_place" ebs_encrypt {
  for_each             = try(data.resource.ebs.result.aws_ebs_volume, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    encrypted = true
  }
}
