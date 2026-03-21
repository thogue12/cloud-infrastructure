resource "azurerm_virtual_network" "this_vnet" {
  name = var.vnet_name
  address_space = var.vnet_address
  location = var.location
  resource_group_name = var.name
}

resource "azurerm_subnet" "this_subnet" {
  name                 = var.subnet_name
  resource_group_name  = var.name
  virtual_network_name = azurerm_virtual_network.this_vnet.name
  address_prefixes     = var.subnet_address
  service_endpoints = [ "Microsoft.Sql", "Microsoft.Storage"] #remember to add this in order to setp the vnet rules on the sql server

  dynamic "delegation" {
    for_each = var.delegation_config
    content {
      name = delegation.value.name
      service_delegation {
        name = delegation.value.service_name
        actions = delegation.value.service_actions
      }
    }
  }
}

resource "azurerm_public_ip" "nat_ip" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "NAT-PIP"
  location            = var.location
  resource_group_name = var.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "this_nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "GlobalAdmin-NatGateway"
  location            = var.location
  resource_group_name = var.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "example" {
  count                 = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this_nat[0].id
  public_ip_address_id = azurerm_public_ip.nat_ip[0].id
}

resource "azurerm_subnet_nat_gateway_association" "nat_association"{
  count                 = var.enable_nat_gateway ? 1 : 0
  subnet_id             = azurerm_subnet.this_subnet.id
  nat_gateway_id        = azurerm_nat_gateway.this_nat[0].id
}