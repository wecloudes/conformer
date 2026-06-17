# Transformation: azure-keyvault-key-rotation — enforce automatic Key Vault key rotation. Azure equivalent of aws-kms-rotation.
#
# Generic (any module). azurerm_key_vault_key with a rotation_policy block
# (automatic key rotation). asraw writes the nested block verbatim, keeping the
# quoted ISO-8601 durations. Empty for_each (no matching resource) = no-op.

data "resource" key_vault_key {
  resource_type = "azurerm_key_vault_key"
}

transform "update_in_place" keyvault_key_rotation {
  for_each             = try(data.resource.key_vault_key.result.azurerm_key_vault_key, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    rotation_policy {
      automatic {
        time_before_expiry = "P30D"
      }

      expire_after         = "P90D"
      notify_before_expiry = "P29D"
    }
  }
}
