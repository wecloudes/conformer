# GENERIC enforcement: Neptune cluster encryption at rest.
#
# Applies to ANY module declaring an aws_neptune_cluster. The typed query matches
# by resource_type, so an empty result (module has no such resource) is a no-op.
# Forces storage_encrypted = true regardless of the caller's var values.

data "resource" neptune {
  resource_type = "aws_neptune_cluster"
}

transform "update_in_place" neptune_encrypt {
  for_each             = try(data.resource.neptune.result.aws_neptune_cluster, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    storage_encrypted = true
  }
}
