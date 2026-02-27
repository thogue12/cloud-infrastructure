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

  delegation {
    name = "functionapp_delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_public_ip" "nat_ip" {
  name                = "NAT-PIP"
  location            = var.location
  resource_group_name = var.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "this_nat" {
  name                = "GlobalAdmin-NatGateway"
  location            = var.location
  resource_group_name = var.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "example" {
  nat_gateway_id       = azurerm_nat_gateway.this_nat.id
  public_ip_address_id = azurerm_public_ip.nat_ip.id
}

resource "azurerm_subnet_nat_gateway_association" "nat_association"{
  subnet_id = azurerm_subnet.this_subnet.id
  nat_gateway_id = azurerm_nat_gateway.this_nat.id
}