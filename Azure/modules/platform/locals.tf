locals {
  random_suffix = random_string.suffix.result
  
  # Resource names
  resource_group_name   = "rg-${var.project_name}-${var.client_name}-${var.environment}"
  vnet_name             = "${var.project_name}-${var.client_name}-vnet-${var.environment}"
  subnet_name           = "MiddleTierInterconnect-${var.environment}"
  sql_server_name       = "${var.project_name}-${var.client_name}-${local.random_suffix}-${var.environment}"
  elasticpool_name      = "${var.project_name}-${var.client_name}-pool-${var.environment}"
  database_name         = "${var.project_name}-${var.client_name}-db-${var.environment}"
  vnet_rule_name        = "${var.project_name}-vnet-rule-${var.environment}" 
  web_app_name          = "${var.project_name}-web-${var.environment}"
  api_app_name          = "${var.project_name}-api-${var.environment}"
  key_vault_name        = "${var.client_name}-${var.project_name}-kv-${local.random_suffix}-${var.environment}"
  storage_account1_name = "${var.client_name}st${local.random_suffix}${var.environment}"
  storage_account2_name = "another${local.random_suffix}${var.environment}"
  # storage_account_name  = "another${local.random_suffix}${var.environment}"  # Added (alias for storage_account2)
  container1_name       = "${var.client_name}-cont-${var.environment}"
  container2_name       = "container${local.random_suffix}${var.environment}"
  # contianer_name        = "container${local.random_suffix}${var.environment}"  # Added (alias for container2)
  function_app_name     = "${var.project_name}-${var.client_name}-func-${var.environment}"  # Added
  web_application_name  = "${var.project_name}-${var.client_name}-webapp-${var.environment}"  # Added
  
  # SQL settings
  admin_login = "${var.project_name}admin"  
  
  # App Service settings
  web_os           = "Windows"  
  api_os           = "Linux"   
  api_sku_name     = var.environment == "prod" ? "P1v2" : "S1"  
  web_app_sku_name = var.environment == "prod" ? "P1v2" : "S1"  
  
  # Key Vault settings
  purge_protection_enabled = var.environment == "prod" ? true : false  
  key_valut_name           = "${var.project_name}-kv-${local.random_suffix}"  
  sku_name                 = "standard"  
  
  # Storage settings
  contianer_access_type = "private" 
  contianer_name_1      = "${var.client_name}-cont"  
  storage_account_name_1 = "${var.client_name}st${local.random_suffix}"  

}