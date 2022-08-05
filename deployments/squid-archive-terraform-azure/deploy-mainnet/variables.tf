variable "name_prefix" {
  type        = string
  description = "Name prefix for most resources"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name parenting resources"
  default     = "bho-squids"
}

variable "resource_group_location" {
  type        = string
  description = "Resource group location"
  default     = "southeastasia"
}

variable "postgres_admin_username" {
  type        = string
  description = "Postgres admin username"
}

variable "postgres_admin_password" {
  type        = string
  description = "Postgres admin password"
}

variable "postgres_location" {
  type        = string
  description = "Postgres database location"
}

variable "postgres_server_sku" {
  type        = string
  description = "Postgres flexible server SKU specs"
  default     = "B_Standard_B2s"
}

variable "chain_endpoints" {
  type = list(object({
    endpoint = string
    capacity = string
  }))
}
