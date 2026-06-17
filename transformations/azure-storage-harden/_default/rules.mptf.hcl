# Transformation: azure-storage-harden — force TLS1.2, HTTPS-only, and block
# public blob access on Storage Accounts. Azure equivalent of aws-s3-public-access
# + S3 SSE/TLS hardening.
#
# Generic (any module). azurerm_storage_account with:
#   - min_tls_version = "TLS1_2"               (TLS floor; SOC2 CC6.7 / NIST SC-8 / PCI 4)
#   - https_traffic_only_enabled = true        (force secure transfer)
#   - allow_nested_items_to_be_public = false  (block public blob/container access; CIS / ISO A.8.3 / SOC2 CC6.1)
# All three are FLAT, in-place-updatable attributes. infrastructure_encryption_enabled
# is intentionally NOT forced — it is ForceNew (forces resource recreation).
# Literal values use asraw — it writes them verbatim KEEPING the quotes. (asstring
# would evaluate the string and emit it unquoted = invalid HCL.) Empty for_each
# (no matching resource) = no-op.

data "resource" sa {
  resource_type = "azurerm_storage_account"
}

transform "update_in_place" storage_harden {
  for_each             = try(data.resource.sa.result.azurerm_storage_account, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    min_tls_version                 = "TLS1_2"
    https_traffic_only_enabled      = true
    allow_nested_items_to_be_public = false
  }
}
