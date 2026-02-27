variable "name" {
  type = string
}
variable "location" {
  type = string
}
variable "purge_protection_enabled" {
  type = bool
}

variable "key_valut_name" {
  type = string
}

variable "sku_name" {
  type = string
  description = "SKU of the key vault can be values such as; 'standard' and 'premium' "
}


