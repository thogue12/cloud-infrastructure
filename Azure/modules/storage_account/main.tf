resource "azurerm_storage_account" "this_storage_account" {
  name                            = var.storage_account_name
  resource_group_name             = var.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "this_container" {
  name                  = var.contianer_name
  storage_account_name    = azurerm_storage_account.this_storage_account.name
  container_access_type = var.contianer_access_type
}
