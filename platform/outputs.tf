output "management_groups" {
  description = "Management group IDs in the flagship hierarchy"
  value = {
    root         = azurerm_management_group.root.id
    platform     = azurerm_management_group.platform.id
    landingzones = azurerm_management_group.landingzones.id
    prod         = azurerm_management_group.prod.id
    dev          = azurerm_management_group.dev.id
  }
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the shared Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Workspace customer ID (for agent registration)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "hub_vnet_id" {
  description = "Hub VNet resource ID (for peering from spokes)"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  value = azurerm_virtual_network.hub.name
}

output "hub_subnet_ids" {
  description = "Hub VNet subnet IDs"
  value = {
    bastion            = azurerm_subnet.bastion.id
    gateway            = azurerm_subnet.gateway.id
    shared_services    = azurerm_subnet.shared_services.id
    private_endpoints  = azurerm_subnet.private_endpoints.id
  }
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs (consumed by spoke stacks)"
  value = {
    for k, z in azurerm_private_dns_zone.main : k => z.id
  }
}

output "network_resource_group_name" {
  value = azurerm_resource_group.platform_network.name
}

output "shared_resource_group_name" {
  value = azurerm_resource_group.platform_shared.name
}
