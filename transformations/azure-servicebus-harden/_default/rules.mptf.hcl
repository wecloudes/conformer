# Transformation: azure-servicebus-harden — enforce TLS, disable SAS/local auth and
# public network access on Service Bus namespaces. Azure equivalent of aws-sqs-encryption.
#
# Generic (any module). azurerm_servicebus_namespace with minimum_tls_version = "1.2"
# (TLS in transit), local_auth_enabled = false (no SAS/local auth, force Entra ID —
# note Service Bus uses local_auth_enabled, NOT local_authentication_enabled),
# public_network_access_enabled = false (private only). asraw keeps literal quotes.
# Empty for_each (no matching resource) = no-op.

data "resource" servicebus {
  resource_type = "azurerm_servicebus_namespace"
}

transform "update_in_place" servicebus_harden {
  for_each             = try(data.resource.servicebus.result.azurerm_servicebus_namespace, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    minimum_tls_version           = "1.2"
    local_auth_enabled            = false
    public_network_access_enabled = false
  }
}
