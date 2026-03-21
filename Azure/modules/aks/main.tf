
resource "azurerm_kubernetes_cluster" "this_aks" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = var.name
  dns_prefix          = var.aks_name

  default_node_pool {
    name           = var.node_name
    node_count     = var.node_count
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  tags = {
    Environment = var.environment
  }
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.this_aks.kube_config[0].client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.this_aks.kube_config_raw

  sensitive = true
}