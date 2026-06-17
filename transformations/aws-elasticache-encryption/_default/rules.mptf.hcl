# Transformation: aws-elasticache-encryption — HARD enforcement for ElastiCache.
#
# Atomic, framework-agnostic, generic (any module). Forces encryption at rest and
# in transit on every aws_elasticache_replication_group. Both are FLAT attributes
# on the resource, so they are overridden with asraw. Typed data source: an empty
# for_each (no matching resources) is a clean no-op.
#
# Control: CIS AWS Foundations / NIST 800-53 SC-28 (encryption at rest) and
# SC-8 (encryption in transit) for cached data.

data "resource" elasticache {
  resource_type = "aws_elasticache_replication_group"
}

transform "update_in_place" elasticache_encryption {
  for_each             = try(data.resource.elasticache.result.aws_elasticache_replication_group, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    at_rest_encryption_enabled = true
    transit_encryption_enabled = true
  }
}
