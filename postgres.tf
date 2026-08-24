data "azurerm_virtual_network" "platform" {
  name                = var.virtual_network_name
  resource_group_name = data.azurerm_resource_group.platform.name
}

data "azurerm_subnet" "database" {
  name                 = var.database_subnet_name
  virtual_network_name = data.azurerm_virtual_network.platform.name
  resource_group_name  = data.azurerm_resource_group.platform.name
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${local.name_prefix}.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.platform.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name_prefix}-dns-link"
  resource_group_name   = data.azurerm_resource_group.platform.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = data.azurerm_virtual_network.platform.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# Detection state: rule definitions, per-tenant tuning, and the rolling window of
# detection events the API serves. It has no public endpoint and sits on the
# delegated database subnet; the cluster resolves it through the private DNS
# zone above.
resource "azurerm_postgresql_flexible_server" "detection" {
  name                = local.name_prefix
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location

  version    = var.postgres_version
  sku_name   = var.postgres_sku_name
  storage_mb = var.postgres_storage_mb
  zone       = "1"

  administrator_login    = var.postgres_administrator_login
  administrator_password = var.postgres_administrator_password

  public_network_access_enabled = false
  delegated_subnet_id           = data.azurerm_subnet.database.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id

  backup_retention_days        = 35
  geo_redundant_backup_enabled = true

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 2
    start_minute = 0
  }

  tags = local.common_tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    # Azure reports back the zone it actually placed the server in, which does not
    # always match the requested one. Without this, every later plan wants to
    # destroy and recreate the server to move it.
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "detection" {
  name      = "detection"
  server_id = azurerm_postgresql_flexible_server.detection.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.detection.id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_disconnections" {
  name      = "log_disconnections"
  server_id = azurerm_postgresql_flexible_server.detection.id
  value     = "on"
}
