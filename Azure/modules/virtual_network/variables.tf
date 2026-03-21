variable "vnet_name" {
  type = string
}

variable "vnet_address" {
  type = list(string)
}

variable "location" {
  type = string
}

variable "name" {
  type = string
}

variable "environment" {
  type        = string
  description = "The environment (dev, test, prod)"
}

variable "subnet_address" {
  type = list(string)
}

variable "subnet_name" {
  type = string
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Determine whether to create the NAT Gateway"
  default     = false
}

variable "delegation_config" {
  description = "List of delegation configurations for the subnet"
  type = list(object({
    name    = string
    service_name    = string
    service_actions = list(string)
  }))
  default = []
}
