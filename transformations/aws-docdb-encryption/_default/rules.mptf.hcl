# GENERIC enforcement: DocumentDB cluster encryption at rest.
#
# Applies to ANY module declaring an aws_docdb_cluster. The typed query matches
# by resource_type, so an empty result (module has no such resource) is a no-op.
# Forces storage_encrypted = true regardless of the caller's var values.

data "resource" docdb {
  resource_type = "aws_docdb_cluster"
}

transform "update_in_place" docdb_encrypt {
  for_each             = try(data.resource.docdb.result.aws_docdb_cluster, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    storage_encrypted = true
  }
}
