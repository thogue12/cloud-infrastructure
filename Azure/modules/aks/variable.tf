variable "aks_name" {
  type        = string
  description = "Name of the AKS cluster"
}

variable "location" {
  type        = string
  description = "Azure region for the AKS cluster"
}

variable "name" {
  type        = string
  description = "Resource group name"
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the default node pool"
  default     = 2
}

variable "node_name" {
  type        = string
  description = "Name of the default node pool"
  default     = "default"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for AKS cluster"
}

variable "environment" {
  type        = string
  description = "Environment: dev, test, or prod"
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "List of IP ranges authorized to access the API server"
  default     = []
}
