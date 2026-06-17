# Transformation: azure-redis-harden — HARD enforcement for Redis caches. Azure equivalent of aws-elasticache-encryption.
#
# Generic (any module). azurerm_redis_cache with minimum_tls_version = "1.2"
# (TLS in transit) and non_ssl_port_enabled = false (close the plaintext 6379 port).
# asraw keeps literal quotes. Empty for_each (no matching resource) = no-op.
#
# Note: the current azurerm attribute is non_ssl_port_enabled (newer form); the
# older enable_non_ssl_port has been superseded.

data "resource" redis {
  resource_type = "azurerm_redis_cache"
}

transform "update_in_place" redis_harden {
  for_each             = try(data.resource.redis.result.azurerm_redis_cache, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    minimum_tls_version  = "1.2"
    non_ssl_port_enabled = false
  }
}
