# Random suffix generator
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

module "resource_group" {
  source      = "../../modules/resource_group"
  name        = local.resource_group_name
  location    = var.location
  environment = var.environment
}

module "virtual_network" {
  source             = "../../modules/virtual_network"
  vnet_name          = local.vnet_name
  vnet_address       = var.vnet_address
  location           = module.resource_group.location
  name               = module.resource_group.resource_group_name
  environment        = var.environment
  subnet_address     = var.subnet_address
  subnet_name        = local.subnet_name
  delegation_config  = local.chosen_delegation
  enable_nat_gateway = var.enable_nat_gateway
}

# Dedicated AKS subnet without delegation
resource "azurerm_subnet" "aks_subnet" {
  name                 = "subnet-aks-nodes-${var.environment}"
  resource_group_name  = module.resource_group.resource_group_name
  virtual_network_name = module.virtual_network.vnet_name
  address_prefixes     = var.aks_subnet_address
}

module "aks" {
  source     = "../../modules/aks"
  aks_name   = local.aks_name
  location   = module.resource_group.location
  name       = module.resource_group.resource_group_name
  node_count = var.node_count
  node_name  = var.node_name
  subnet_id  = azurerm_subnet.aks_subnet.id
  environment = var.environment
}
