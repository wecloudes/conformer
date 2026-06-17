# Transformation: azure-cosmosdb-harden — HARD enforcement for Cosmos DB accounts. Azure equivalent of aws-dynamodb-encryption.
#
# Generic (any module). azurerm_cosmosdb_account with minimal_tls_version = "Tls12"
# (TLS in transit) and local_authentication_enabled = false (force Entra ID / MSI,
# disable shared-key auth). asraw keeps literal quotes. Empty for_each (no matching
# resource) = no-op.
#
# Note: the value is "Tls12" (Cosmos-specific casing), NOT "TLS1_2". The disable
# control is the positive boolean local_authentication_enabled = false; there is no
# local_authentication_disabled attribute on this resource.

data "resource" cosmos {
  resource_type = "azurerm_cosmosdb_account"
}

transform "update_in_place" cosmosdb_harden {
  for_each             = try(data.resource.cosmos.result.azurerm_cosmosdb_account, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    minimal_tls_version           = "Tls12"
    local_authentication_enabled  = false
  }
}
