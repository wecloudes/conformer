# Transformation: azure-functionapp-harden — force HTTPS-only on Function Apps.
# Azure equivalent of aws-lambda-tracing (serverless tier hardening).
#
# Generic (any module). azurerm_linux_function_app + azurerm_windows_function_app
# with https_only = true (CIS Azure / encryption in transit). asraw keeps literal
# values verbatim. Empty for_each (no matching resource) = no-op.

data "resource" linux_fn {
  resource_type = "azurerm_linux_function_app"
}

transform "update_in_place" linux_fn_https {
  for_each             = try(data.resource.linux_fn.result.azurerm_linux_function_app, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    https_only = true
  }
}

data "resource" windows_fn {
  resource_type = "azurerm_windows_function_app"
}

transform "update_in_place" windows_fn_https {
  for_each             = try(data.resource.windows_fn.result.azurerm_windows_function_app, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    https_only = true
  }
}
