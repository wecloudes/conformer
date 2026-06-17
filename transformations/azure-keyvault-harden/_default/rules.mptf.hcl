# Transformation: azure-keyvault-harden — enforce Key Vault purge protection. Azure equivalent of aws-kms key management hygiene.
#
# Generic (any module). azurerm_key_vault with purge_protection_enabled (key
# deletion/recovery protection — prevents permanent purge of the vault). asraw
# writes the value verbatim. Empty for_each (no matching resource) = no-op.

data "resource" key_vault {
  resource_type = "azurerm_key_vault"
}

transform "update_in_place" keyvault_harden {
  for_each             = try(data.resource.key_vault.result.azurerm_key_vault, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    purge_protection_enabled = true
  }
}
