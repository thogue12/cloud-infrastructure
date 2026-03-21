locals {
  random_suffix = random_string.suffix.result
  
  # Resource names
  resource_group_name   = "rg-${var.project_name}-${var.environment}"
  vnet_name             = "${var.project_name}-vnet-${var.environment}"
  subnet_name           = "subnet-aks-${var.environment}"
  aks_name              = "${var.project_name}-aks-${var.environment}"
  sql_server_name       = "${var.project_name}-${local.random_suffix}-${var.environment}"
  elasticpool_name      = "${var.project_name}-pool-${var.environment}"
  key_vault_name        = "${var.project_name}-kv-${local.random_suffix}-${var.environment}"
  storage_account1_name = "${var.project_name}st${local.random_suffix}${var.environment}"
  storage_account2_name = "another${local.random_suffix}${var.environment}"
  container1_name       = "cont-${var.environment}"
  container2_name       = "container${local.random_suffix}${var.environment}"
  function_app_name     = "${var.project_name}-func-${var.environment}"
  web_application_name  = "${var.project_name}-webapp-${var.environment}"
    
  # Key Vault settings
  purge_protection_enabled = var.environment == "prod" ? true : false  
  key_vault_name_short     = "${var.project_name}-kv-${local.random_suffix}"  
  sku_name                 = "standard"  
  
  # Storage settings
  contianer_access_type = "private" 
  contianer_name_1      = "cont"  
  storage_account_name_1 = "${var.project_name}st${local.random_suffix}"  

# Subnet delegation
  standard_delegation = {
    name  = "functionapp_delegation"
    service_name  = "Microsoft.Web/serverFarms"
    service_actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
  }
  chosen_delegation = var.should_delegate ? [local.standard_delegation] : []

}