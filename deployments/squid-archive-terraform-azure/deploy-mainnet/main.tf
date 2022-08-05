terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.15.1"
    }
  }

  backend "azurerm" {
    resource_group_name  = "bho-tf"
    storage_account_name = "bhosquidstfstate"
    container_name       = "bhosquidstfstate"
    key                  = "squid-archive.mainnet.tfstate"
  }
}

provider "azurerm" {
  features {

  }
}

module "squid_archive" {
  source = "../modules/squid-archive"

  resource_group_name     = var.resource_group_name
  resource_group_location = var.resource_group_location

  name_prefix = var.name_prefix

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
  postgres_location       = var.postgres_location
  postgres_server_sku     = var.postgres_server_sku

  chain_endpoints = var.chain_endpoints
}
