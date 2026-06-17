# Transformation: azure-acr-harden — disable admin user + anonymous pull on ACR.
# Azure equivalent of aws-ecr-harden.
#
# Generic (any module). azurerm_container_registry with admin_enabled = false +
# anonymous_pull_enabled = false (CIS Azure / least-privilege registry access).
# asraw keeps literal values verbatim. Empty for_each (no matching resource) = no-op.

data "resource" acr {
  resource_type = "azurerm_container_registry"
}

transform "update_in_place" acr_harden {
  for_each             = try(data.resource.acr.result.azurerm_container_registry, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    admin_enabled          = false
    anonymous_pull_enabled = false
  }
}
