# Transformation: azure-loganalytics-retention — enforce 1-year log retention. Azure equivalent of aws-cloudwatch-log-retention.
#
# Generic (any module). azurerm_log_analytics_workspace with retention_in_days
# (ensure workspace logs are retained, not left at a short default). asraw
# writes the value verbatim. Empty for_each (no matching resource) = no-op.

data "resource" log_analytics_workspace {
  resource_type = "azurerm_log_analytics_workspace"
}

transform "update_in_place" loganalytics_retention {
  for_each             = try(data.resource.log_analytics_workspace.result.azurerm_log_analytics_workspace, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    retention_in_days = 365
  }
}
