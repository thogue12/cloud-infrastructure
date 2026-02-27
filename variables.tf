# Required inputs for platform module
variable "azure_subscription_id" {
  type      = string
  sensitive = true
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "client_name" {
  description = "client name for resource naming"
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

variable "admin_login_password" {
  description = "SQL Server admin password"
  type        = string
  sensitive   = true
}

# Optional inputs
variable "database_count" {
  description = "Number of databases to create"
  type        = number
  default     = 1
}

variable "subnet_address" {
  description = "Subnet address space"
  type        = list(string)
}

variable "vnet_address" {
  description = "VNet address space"
  type        = list(string)
}
