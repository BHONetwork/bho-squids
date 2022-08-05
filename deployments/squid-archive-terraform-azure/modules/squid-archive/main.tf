resource "azurerm_resource_group" "default" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_virtual_network" "default" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  address_space       = ["10.0.0.0/16"]
}

// POSTGRES setups

resource "azurerm_network_security_group" "postgres" {
  name                = "${var.name_prefix}-postgres-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_subnet" "postgres" {
  name                 = "${var.name_prefix}-postgres-subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }

  depends_on = [
    azurerm_virtual_network.default
  ]
}

resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.postgres.id
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name_prefix}-pdz.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.default.name

  depends_on = [azurerm_subnet_network_security_group_association.postgres]
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name_prefix}-postgres-pdzvnetlink.com"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.default.id
  resource_group_name   = azurerm_resource_group.default.name
}

resource "azurerm_postgresql_flexible_server" "default" {
  name                   = "${var.name_prefix}-server"
  resource_group_name    = azurerm_resource_group.default.name
  location               = var.postgres_location
  version                = "13"
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password
  zone                   = "1"
  storage_mb             = 131072 // 128 GiB
  sku_name               = var.postgres_server_sku
  backup_retention_days  = 7

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "default" {
  name      = "${var.name_prefix}-db"
  server_id = azurerm_postgresql_flexible_server.default.id
  collation = "en_US.UTF8"
  charset   = "UTF8"
}

locals {
  postgres_host              = azurerm_postgresql_flexible_server.default.fqdn
  postgres_db                = azurerm_postgresql_flexible_server_database.default.name
  postgres_connection_string = "postgres://${var.postgres_admin_username}:${var.postgres_admin_password}@${local.postgres_host}:5432/${local.postgres_db}?sslmode=require"
}

// SUBSTRATE-INGEST setups
resource "azurerm_network_security_group" "archive_ingest" {
  name                = "${var.name_prefix}-archive-ingest-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_subnet" "archive_ingest" {
  name                 = "${var.name_prefix}-archive-ingest-subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "delegation"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  depends_on = [
    azurerm_virtual_network.default
  ]
}

resource "azurerm_subnet_network_security_group_association" "archive_ingest" {
  subnet_id                 = azurerm_subnet.archive_ingest.id
  network_security_group_id = azurerm_network_security_group.archive_ingest.id
}


resource "azurerm_network_profile" "archive_ingest" {
  name                = "${var.name_prefix}-archive-ingest-networkprofile"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name

  container_network_interface {
    name = "${var.name_prefix}-archive-ingest-nic"

    ip_configuration {
      name      = "${var.name_prefix}-archive-ingest-ipconfig"
      subnet_id = azurerm_subnet.archive_ingest.id
    }
  }
}

resource "azurerm_container_group" "archive_ingest" {
  name                = "${var.name_prefix}-archive-ingest-coninst"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  ip_address_type     = "Private"
  network_profile_id  = azurerm_network_profile.archive_ingest.id
  os_type             = "Linux"
  restart_policy      = "Never"
  exposed_port = [{
    port     = 9090
    protocol = "TCP"
  }]

  container {
    name   = "${var.name_prefix}-archive-ingest"
    image  = "subsquid/substrate-ingest:firesquid"
    cpu    = "2"
    memory = "2"

    ports {
      port     = 9090
      protocol = "TCP"
    }

    commands = flatten(["node", "/squid/substrate-ingest/bin/run.js",
      [for endpoint in var.chain_endpoints : ["-e", "${endpoint.endpoint}", "-c", "${endpoint.capacity}"]],
      ["--prom-port", "9090"],
    ["--out", local.postgres_connection_string]])
  }

  tags = {
    environment = "testnet"
  }
}

// SUBSTRATE-GATEWAY setups

resource "azurerm_network_security_group" "archive_gateway" {
  name                = "${var.name_prefix}-archive-gateway-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_subnet" "archive_gateway" {
  name                 = "${var.name_prefix}-archive-gateway-subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.3.0/24"]

  delegation {
    name = "delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  depends_on = [
    azurerm_virtual_network.default
  ]
}

resource "azurerm_subnet_network_security_group_association" "archive_gateway" {
  subnet_id                 = azurerm_subnet.archive_gateway.id
  network_security_group_id = azurerm_network_security_group.archive_gateway.id
}

resource "azurerm_service_plan" "archive_gateway" {
  name                = "${var.name_prefix}-archive-gateway-sp"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  os_type             = "Linux"
  sku_name            = "B2"
  worker_count        = 2
}

resource "azurerm_linux_web_app" "archive_gateway" {
  name                      = "${var.name_prefix}-archive-gateway-app"
  location                  = azurerm_resource_group.default.location
  resource_group_name       = azurerm_resource_group.default.name
  service_plan_id           = azurerm_service_plan.archive_gateway.id
  virtual_network_subnet_id = azurerm_subnet.archive_gateway.id


  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  site_config {
    app_command_line = "--database-url ${local.postgres_connection_string} --database-max-connections 3 --contracts-support --evm-support"

    application_stack {
      docker_image     = "subsquid/substrate-gateway"
      docker_image_tag = "firesquid"
    }
  }
}

// SUBSTRATE-EXPLORER setups

resource "azurerm_network_security_group" "archive_explorer" {
  name                = "${var.name_prefix}-archive-explorer-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_subnet" "archive_explorer" {
  name                 = "${var.name_prefix}-archive-explorer-subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.4.0/24"]

  delegation {
    name = "delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  depends_on = [
    azurerm_virtual_network.default
  ]
}

resource "azurerm_subnet_network_security_group_association" "archive_explorer" {
  subnet_id                 = azurerm_subnet.archive_explorer.id
  network_security_group_id = azurerm_network_security_group.archive_explorer.id
}

resource "azurerm_service_plan" "archive_explorer" {
  name                = "${var.name_prefix}-archive-explorer-sp"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  os_type             = "Linux"
  sku_name            = "B2"
  worker_count        = 2
}

resource "azurerm_linux_web_app" "archive_explorer" {
  name                      = "${var.name_prefix}-archive-explorer-app"
  location                  = azurerm_resource_group.default.location
  resource_group_name       = azurerm_resource_group.default.name
  service_plan_id           = azurerm_service_plan.archive_explorer.id
  virtual_network_subnet_id = azurerm_subnet.archive_explorer.id


  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "WEBSITE_WARMUP_PATH"                 = "/graphql"
    "DB_TYPE"                             = "postgres"
    "DB_HOST"                             = local.postgres_host
    "DB_PORT"                             = "5432"
    "DB_NAME"                             = local.postgres_db
    "DB_USER"                             = var.postgres_admin_username
    "DB_PASS"                             = var.postgres_admin_password
  }

  site_config {

    application_stack {
      docker_image     = "subsquid/substrate-explorer"
      docker_image_tag = "firesquid"
    }
  }
}
