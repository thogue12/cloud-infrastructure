# Resource Group outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.resource_group_name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = module.resource_group.resource_group_id
}

# SQL Server outputs
output "sql_server_id" {
  description = "ID of the SQL Server"
  value       = module.sql_server.sql_server_id
}

# Virtual Network outputs
output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = module.virtual_network.virtual_network_id
}

output "virtual_network_name" {
  description = "ID of the virtual network"
  value       = module.virtual_network.virtual_network_name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.virtual_network.subnet_id
}

# Storage Account outputs
output "storage_account_name" {
  description = "Name of the primary storage account"
  value       = module.storage_account.storage_account_name
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = module.storage_account.storage_account_primary_key
  sensitive   = true
}

# Key Vault outputs
output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = module.key_vault.key_vault_id
}

# App Service Plan outputs
output "app_service_plan_id" {
  description = "ID of the API app service plan"
  value       = module.app_service_plan.app_service_plan_id
}

output "web_app_service_plan_id" {
  description = "ID of the web app service plan"
  value       = module.app_service_plan.web_app_service_plan_id
}
