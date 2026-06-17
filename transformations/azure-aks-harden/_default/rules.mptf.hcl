# Transformation: azure-aks-harden — disable local accounts, force RBAC + Azure Policy.
# Azure equivalent of aws-eks-audit-logs.
#
# Generic (any module). azurerm_kubernetes_cluster with local_account_disabled = true,
# role_based_access_control_enabled = true, azure_policy_enabled = true (CIS AKS /
# AAD-managed access + policy enforcement). asraw keeps literal values verbatim.
# Empty for_each (no matching resource) = no-op.

data "resource" aks {
  resource_type = "azurerm_kubernetes_cluster"
}

transform "update_in_place" aks_harden {
  for_each             = try(data.resource.aks.result.azurerm_kubernetes_cluster, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    local_account_disabled            = true
    role_based_access_control_enabled = true
    azure_policy_enabled              = true
  }
}
