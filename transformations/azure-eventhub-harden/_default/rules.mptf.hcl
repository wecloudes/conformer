# Transformation: azure-eventhub-harden — enforce TLS, disable SAS/local auth and
# public network access on Event Hubs namespaces. Azure equivalent of aws-msk-encryption.
#
# Generic (any module). azurerm_eventhub_namespace with minimum_tls_version = "1.2"
# (TLS in transit), local_authentication_enabled = false (no SAS/local auth, force
# Entra ID), public_network_access_enabled = false (private only). asraw keeps literal
# quotes. Empty for_each (no matching resource) = no-op.

data "resource" eventhub {
  resource_type = "azurerm_eventhub_namespace"
}

transform "update_in_place" eventhub_harden {
  for_each             = try(data.resource.eventhub.result.azurerm_eventhub_namespace, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    minimum_tls_version           = "1.2"
    local_authentication_enabled  = false
    public_network_access_enabled = false
  }
}
