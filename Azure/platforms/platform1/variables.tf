# Required inputs (no defaults)
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


variable "subnet_address" {
  type =  list(string)
}

variable "vnet_address" {
  type =  list(string)
}

variable "should_delegate" {
  type = bool
  description = "Determine whether or not the subnet delegation should be created"
  default = true
}

variable "enable_nat_gateway" {
  type = bool
  description = "Determine whether you need to create the NATGW"
}
