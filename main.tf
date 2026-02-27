terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}


module "platform" {
  source               = "./Azure/modules/platform"
  environment          = var.environment
  project_name         = var.project_name
  location             = var.location
  admin_login_password = var.admin_login_password
  subnet_address       = var.subnet_address
  vnet_address         = var.vnet_address
  client_name          = var.client_name


}

terraform {
  backend "azurerm" {
    resource_group_name  = "tf_state"
    storage_account_name = ""
    container_name       = ""
    key                  = ""
  }
}