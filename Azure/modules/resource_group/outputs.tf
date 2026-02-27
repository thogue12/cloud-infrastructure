output "resource_group_name" {
  value = azurerm_resource_group.this-rg.name
}

output "resource_group_id" {
  value = azurerm_resource_group.this-rg.id
}


output "location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.this-rg.location
}