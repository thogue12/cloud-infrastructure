
######################################################################
## Sql Server
######################################################################
resource "azurerm_mssql_server" "this_sql_server" {
  name                          = var.sql_server_name
  resource_group_name           = var.name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = var.admin_login
  administrator_login_password  = var.admin_login_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

#   azuread_administrator {
#     login_username = var.aad_admin_login
#     object_id      = var.aad_admin_object_id
#   }
}

resource "azurerm_mssql_server_transparent_data_encryption" "this_tde" {
  server_id = azurerm_mssql_server.this_sql_server.id
}

resource "azurerm_mssql_server_extended_auditing_policy" "this_audit_policy" {
  server_id         = azurerm_mssql_server.this_sql_server.id
  retention_in_days = 90
}

resource "azurerm_mssql_virtual_network_rule" "this_vnet_rule" {
  name      = var.vnet_rule_name
  server_id = azurerm_mssql_server.this_sql_server.id
  subnet_id = var.subnet_id
}

######################################################################
## Elastic Pool
######################################################################
resource "azurerm_mssql_elasticpool" "this_elastic_pool" {
  name                = var.elasticpool_name
  resource_group_name = var.name
  location            = var.location
  server_name         = azurerm_mssql_server.this_sql_server.name
  license_type        = "LicenseIncluded"
  max_size_gb         = 50

  sku {
    name     = "StandardPool"
    tier     = "Standard"
    capacity = var.edtu
  }

  per_database_settings {
    min_capacity = 0
    max_capacity = 50
  }
}

######################################################################
## Sql database
######################################################################
resource "azurerm_mssql_database" "this_db" {
  name            = var.database_name
  server_id       = azurerm_mssql_server.this_sql_server.id
  elastic_pool_id = azurerm_mssql_elasticpool.this_elastic_pool.id
  collation       = "SQL_Latin1_General_CP1_CI_AS"
  license_type    = "LicenseIncluded"

  lifecycle {
    prevent_destroy = false
  }
}
