# Transformation: azure-appservice-harden — force HTTPS-only on Web Apps.
# Azure equivalent of aws-lambda-tracing applied to the web app service tier.
#
# Generic (any module). azurerm_linux_web_app + azurerm_windows_web_app with
# https_only = true (CIS Azure / encryption in transit). asraw keeps literal
# values verbatim. Empty for_each (no matching resource) = no-op.

data "resource" linux_web {
  resource_type = "azurerm_linux_web_app"
}

transform "update_in_place" linux_web_https {
  for_each             = try(data.resource.linux_web.result.azurerm_linux_web_app, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    https_only = true
  }
}

data "resource" windows_web {
  resource_type = "azurerm_windows_web_app"
}

transform "update_in_place" windows_web_https {
  for_each             = try(data.resource.windows_web.result.azurerm_windows_web_app, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    https_only = true
  }
}
