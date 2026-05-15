################################################################################
# Log Analytics workspace
#
# Single shared workspace for the entire flagship project. All diagnostic
# settings and App Insights will reference this.
#
# Cost control:
#   - PerGB2018 SKU: pay only for what we ingest
#   - Daily quota: 1GB/day (33GB/month, well over our actual needs)
#   - Retention: 30 days (free for the first 31 days)
#   - Free grant: 5GB/month, so ~$0/month at our scale
################################################################################

resource "azurerm_resource_group" "platform_shared" {
  name     = "rg-flagship-platform-shared"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-flagship-shared-${local.region_short}"
  resource_group_name = azurerm_resource_group.platform_shared.name
  location            = azurerm_resource_group.platform_shared.location

  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days
  daily_quota_gb    = var.log_analytics_daily_cap_gb

  internet_ingestion_enabled = true   # required until we add private endpoints
  internet_query_enabled     = true

  tags = local.common_tags
}

# Alert when daily cap is approached, so we know if something's spamming logs.
resource "azurerm_monitor_action_group" "platform_alerts" {
  name                = "ag-flagship-platform"
  resource_group_name = azurerm_resource_group.platform_shared.name
  short_name          = "platform"

  email_receiver {
    name                    = "owner"
    email_address           = "victor.ugbor30@gmail.com"  # TODO: source from variable on Day 3
    use_common_alert_schema = true
  }

  tags = local.common_tags
}
