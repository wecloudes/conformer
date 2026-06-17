# Transformation: azure-search-harden — disable API-key/local auth and public network
# access on Azure Cognitive Search services. Azure equivalent of aws-opensearch-harden.
#
# Generic (any module). azurerm_search_service with local_authentication_enabled = false
# (no API keys, force Entra ID RBAC) and public_network_access_enabled = false (private
# only). Both are bool args (confirmed against azurerm docs; public access is the bool
# public_network_access_enabled, not a string enum). asraw keeps literal values. Empty
# for_each (no matching resource) = no-op.

data "resource" search {
  resource_type = "azurerm_search_service"
}

transform "update_in_place" search_harden {
  for_each             = try(data.resource.search.result.azurerm_search_service, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    local_authentication_enabled  = false
    public_network_access_enabled = false
  }
}
