
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "primary" {}

resource "azurerm_key_vault" "this_key_vault" {
  name                        = var.key_valut_name
  location                    = var.location
  resource_group_name         = var.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = var.purge_protection_enabled

  sku_name = var.sku_name

}
resource "azurerm_role_assignment" "key_vault_admin" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_role_assignment" "key_vault_secretes" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_client_config.current.object_id
}
