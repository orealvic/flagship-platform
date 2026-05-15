################################################################################
# Hub VNet + Private DNS zones
#
# Hub VNet 10.10.0.0/16 in Canada Central:
#   - AzureBastionSubnet  10.10.1.0/26   (Bastion deployed on-demand later)
#   - GatewaySubnet       10.10.2.0/27   (VPN Gateway deployed on-demand later)
#   - SharedServices      10.10.10.0/24  (private DNS resolver, etc.)
#   - PrivateEndpoints    10.10.20.0/24  (PEs for shared services)
#
# Private DNS zones for services we'll add in Days 3-5:
#   - privatelink.blob.core.windows.net
#   - privatelink.vaultcore.azure.net
#   - privatelink.mysql.database.azure.com
#   - privatelink.openai.azure.com
#   - privatelink.azurewebsites.net
#
# Each zone is linked to the hub VNet so name resolution works as soon as
# we attach spokes via peering.
################################################################################

resource "azurerm_resource_group" "platform_network" {
  name     = "rg-flagship-platform-network"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-flagship-hub-${local.region_short}"
  resource_group_name = azurerm_resource_group.platform_network.name
  location            = azurerm_resource_group.platform_network.location
  address_space       = var.hub_vnet_address_space

  tags = local.common_tags
}

# Subnets — Bastion and Gateway names are fixed by Azure.
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.platform_network.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.1.0/26"]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.platform_network.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.2.0/27"]
}

resource "azurerm_subnet" "shared_services" {
  name                 = "snet-shared-services"
  resource_group_name  = azurerm_resource_group.platform_network.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.10.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.platform_network.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.20.0/24"]
}

# NSG for the shared-services subnet — default-deny inbound from Internet.
resource "azurerm_network_security_group" "shared_services" {
  name                = "nsg-flagship-shared-services"
  resource_group_name = azurerm_resource_group.platform_network.name
  location            = azurerm_resource_group.platform_network.location
  tags                = local.common_tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "shared_services" {
  subnet_id                 = azurerm_subnet.shared_services.id
  network_security_group_id = azurerm_network_security_group.shared_services.id
}

# Same posture on the PE subnet.
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-flagship-private-endpoints"
  resource_group_name = azurerm_resource_group.platform_network.name
  location            = azurerm_resource_group.platform_network.location
  tags                = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# ─── Private DNS zones ─────────────────────────────────────────────────────

locals {
  private_dns_zones = {
    blob       = "privatelink.blob.core.windows.net"
    keyvault   = "privatelink.vaultcore.azure.net"
    mysql      = "privatelink.mysql.database.azure.com"
    openai     = "privatelink.openai.azure.com"
    appservice = "privatelink.azurewebsites.net"
    cosmos     = "privatelink.documents.azure.com"
  }
}

resource "azurerm_private_dns_zone" "main" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.platform_network.name
  tags                = local.common_tags
}

# Link each zone to the hub VNet so resolution works from anything peered.
resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = local.private_dns_zones
  name                  = "pdz-link-hub-${each.key}"
  resource_group_name   = azurerm_resource_group.platform_network.name
  private_dns_zone_name = azurerm_private_dns_zone.main[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.common_tags
}
