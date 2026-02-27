
# Random suffix generator
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

module "resource_group" {
  source      = "../resource_group"
  name        = local.resource_group_name
  location    = var.location
  environment = var.environment

}

module "virtual_network" {
  source         = "../virtual_network"
  vnet_name      = local.vnet_name
  vnet_address   = var.vnet_address
  location       = module.resource_group.location
  name           = module.resource_group.resource_group_name
  environment    = var.environment
  subnet_address = var.subnet_address
  subnet_name    = local.subnet_name
}

module "sql_server" {
  source               = "../sql_server"
  sql_server_name      = local.sql_server_name
  admin_login          = local.admin_login
  admin_login_password = var.admin_login_password
  location             = module.resource_group.location
  name                 = module.resource_group.resource_group_name
  subnet_id            = module.virtual_network.subnet_id
  elasticpool_name     = local.elasticpool_name
  vnet_rule_name       = local.vnet_rule_name
  database_name        = local.database_name
  database_count       = var.database_count
}

module "app_service_plan" {
  source             = "../app_service_plan"
  location           = module.resource_group.location
  name               = module.resource_group.resource_group_name
  web_app_name       = local.web_app_name
  api_app_name       = local.api_app_name
  web_os             = local.web_os
  api_os             = local.api_os
  sql_server_id      = module.sql_server.sql_server_id
  virtual_network_id = module.virtual_network.virtual_network_id
  api_sku_name       = local.api_sku_name
  web_app_sku_name   = local.web_app_sku_name
}

module "key_vault" {
  source                   = "../key_vault"
  purge_protection_enabled = local.purge_protection_enabled
  key_valut_name           = local.key_valut_name
  sku_name                 = local.sku_name
  location                 = module.resource_group.location
  name                     = module.resource_group.resource_group_name

}

###############################################################################################################################
# Storage Account
###############################################################################################################################
module "storage_account" {
  source                = "../storage_account"
  contianer_access_type = local.contianer_access_type
  contianer_name        = local.contianer_name_1
  storage_account_name  = local.storage_account_name_1
  name                  = module.resource_group.resource_group_name
  location              = module.resource_group.location
}

module "storage_account2" {
  source                = "../storage_account"
  contianer_access_type = local.contianer_access_type
  contianer_name        = local.container2_name
  storage_account_name  = local.storage_account2_name #storage account name must be globally unique and no 'dashes -' allowed
  name                  = module.resource_group.resource_group_name
  location              = module.resource_group.location
}

module "function_app" {
  source                     = "../function_app"
  name                       = module.resource_group.resource_group_name
  location                   = module.resource_group.location
  function_app_name          = local.function_app_name
  storage_account_access_key = module.storage_account.storage_account_primary_key
  storage_account_name       = module.storage_account.storage_account_name
  app_service_plan_id        = module.app_service_plan.app_service_plan_id
  subnet_id                  = module.virtual_network.subnet_id
}

module "web_app" {
  source                  = "../web_app"
  name                    = module.resource_group.resource_group_name
  location                = module.resource_group.location
  web_app_service_plan_id = module.app_service_plan.web_app_service_plan_id
  web_application_name    = local.web_application_name
}