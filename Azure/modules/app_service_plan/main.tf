resource "azurerm_service_plan" "web_app" {
  name                = var.web_app_name
  resource_group_name = var.name
  location            = var.location
  os_type             = var.web_os
  sku_name            = var.web_app_sku_name
}

resource "azurerm_service_plan" "api_app" {
  name                = var.api_app_name
  resource_group_name = var.name
  location            = var.location
  os_type             = var.api_os
  sku_name            = var.api_sku_name
}