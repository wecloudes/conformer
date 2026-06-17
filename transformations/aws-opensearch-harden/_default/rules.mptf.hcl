# GENERIC enforcement: OpenSearch domain hardening.
#
# Applies to ANY module declaring an aws_opensearch_domain. The typed query
# matches by resource_type, so an empty result (module has no such resource) is
# a no-op. These controls are expressed as NESTED blocks (encrypt_at_rest,
# node_to_node_encryption, domain_endpoint_options), so the transforms use
# asstring to emit real HCL blocks rather than raw attribute values:
#   - encrypt_at_rest        { enabled = true }       encryption at rest
#   - node_to_node_encryption{ enabled = true }       node-to-node TLS
#   - domain_endpoint_options{ enforce_https = true } HTTPS-only endpoint
# Forces all three regardless of the caller's var values.

data "resource" opensearch {
  resource_type = "aws_opensearch_domain"
}

transform "update_in_place" opensearch_encrypt_at_rest {
  for_each             = try(data.resource.opensearch.result.aws_opensearch_domain, {})
  target_block_address = each.value.mptf.block_address
  asstring {
    encrypt_at_rest {
      enabled = true
    }
  }
}

transform "update_in_place" opensearch_node_to_node_encryption {
  for_each             = try(data.resource.opensearch.result.aws_opensearch_domain, {})
  target_block_address = each.value.mptf.block_address
  asstring {
    node_to_node_encryption {
      enabled = true
    }
  }
}

transform "update_in_place" opensearch_domain_endpoint_options {
  for_each             = try(data.resource.opensearch.result.aws_opensearch_domain, {})
  target_block_address = each.value.mptf.block_address
  asstring {
    domain_endpoint_options {
      enforce_https = true
    }
  }
}
