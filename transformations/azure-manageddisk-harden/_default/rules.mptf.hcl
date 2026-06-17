# Transformation: azure-manageddisk-harden — disable public network access on
# Managed Disks. Azure equivalent of aws-ebs-encryption.
#
# Generic (any module). azurerm_managed_disk with:
#   - public_network_access_enabled = false  (network control; NIST SC-7 / CIS)
# Azure Managed Disks are ALWAYS encrypted at rest by the platform, so there is
# no encrypt-at-rest toggle to force (unlike EBS encrypted = true). We force the
# network control instead — disallow disk access over the public network.
# This is a FLAT, in-place-updatable bool. Literal bool uses asraw (verbatim).
# Empty for_each (no matching resource) = no-op.

data "resource" md {
  resource_type = "azurerm_managed_disk"
}

transform "update_in_place" manageddisk_harden {
  for_each             = try(data.resource.md.result.azurerm_managed_disk, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    public_network_access_enabled = false
  }
}
