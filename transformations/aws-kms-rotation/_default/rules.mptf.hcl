# GENERIC enforcement: KMS key rotation (CIS AWS Foundations 3.8).
#
# Applies to ANY module declaring an aws_kms_key. The typed query matches by
# resource_type, so an empty result (module has no such resource) is a no-op.
# Forces enable_key_rotation = true regardless of the caller's var values.

data "resource" kms {
  resource_type = "aws_kms_key"
}

transform "update_in_place" kms_rotation {
  for_each             = try(data.resource.kms.result.aws_kms_key, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    enable_key_rotation = true
  }
}
