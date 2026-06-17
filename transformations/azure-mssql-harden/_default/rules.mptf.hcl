# Transformation: azure-mssql-harden — HARD enforcement for Azure managed databases. Azure equivalent of aws-rds-harden.
#
# Generic (any module). Three resources, one transform each:
#   azurerm_mssql_server              -> minimum_tls_version = "1.2", public_network_access_enabled = false
#   azurerm_postgresql_flexible_server -> public_network_access_enabled = false
#   azurerm_mysql_flexible_server      -> public_network_access = "Disabled"
# asraw keeps literal quotes. Empty for_each (no matching resource) = no-op.
#
# Note: mssql_server and postgresql_flexible_server use the boolean
# public_network_access_enabled. mysql_flexible_server uses public_network_access
# with string values "Enabled"/"Disabled" (the boolean form was removed in
# azurerm 5.0), so it is "Disabled" here.

data "resource" mssql {
  resource_type = "azurerm_mssql_server"
}

data "resource" postgres {
  resource_type = "azurerm_postgresql_flexible_server"
}

data "resource" mysql {
  resource_type = "azurerm_mysql_flexible_server"
}

transform "update_in_place" mssql_harden {
  for_each             = try(data.resource.mssql.result.azurerm_mssql_server, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    minimum_tls_version           = "1.2"
    public_network_access_enabled = false
  }
}

transform "update_in_place" postgres_harden {
  for_each             = try(data.resource.postgres.result.azurerm_postgresql_flexible_server, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    public_network_access_enabled = false
  }
}

transform "update_in_place" mysql_harden {
  for_each             = try(data.resource.mysql.result.azurerm_mysql_flexible_server, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    public_network_access = "Disabled"
  }
}
