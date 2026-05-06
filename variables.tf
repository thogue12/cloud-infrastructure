# Required inputs for platform module
variable "azure_subscription_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment: dev, test, or prod"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_address" {
  description = "Subnet address space"
  type        = list(string)
}

# variable "aks_subnet_address" {
#   description = "AKS subnet address space (must not overlap with subnet_address)"
#   type        = list(string)
# }

variable "vnet_address" {
  description = "VNet address space"
  type        = list(string)
}

# variable "node_count" {
#   description = "Number of nodes in the default node pool"
#   type        = number
#   default     = 2
# }

# variable "node_name" {
#   description = "Name of the default node pool"
#   type        = string
#   default     = "default"
# }


# variable "should_delegate" {
#   type = bool
#   description = "Determine whether or not the subnet delegation should be created"
# }

variable "enable_nat_gateway" {
  type = bool
  description = "Determine whether you need to create the NATGW"
}
variable "admin_login_password" {
  description = "SQL Server admin password"
  type        = string
  sensitive   = true
  default     = "Timosbuodf1290#$%"
}
variable "client_name" {
  description = "client name for resource naming"
  type        = string
}
variable "web_app_sku_name" {
  type = string
  description = "can be B2, B3, D1, F1,I2-3,P1v2,P2v2, S1-3"
}

variable "api_sku_name" {
  type = string
  description = "can be B2, B3, D1, F1,I2-3,P1v2,P2v2, S1-3"
}
