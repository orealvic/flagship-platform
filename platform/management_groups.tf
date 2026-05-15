################################################################################
# Management group hierarchy
#
#   tg-flagship (root, parent = tenant root)
#     ├── tg-flagship-platform        (shared services — empty for now)
#     └── tg-flagship-landingzones    (workload subs go here)
#           ├── tg-flagship-prod      (this subscription, scoped for prod resources)
#           └── tg-flagship-dev       (would hold a separate dev sub at scale —
#                                      for the credit project, dev shares this sub)
#
# Resource: azurerm_management_group
#   Note: MGs can take 30-60s to fully propagate. Subscription placement may
#   require a retry on the first run.
################################################################################

resource "azurerm_management_group" "root" {
  name         = local.mg_root
  display_name = "Flagship (root)"
  # Parent: tenant root group (parent_management_group_id omitted = root)
}

resource "azurerm_management_group" "platform" {
  name                       = local.mg_platform
  display_name               = "Flagship — Platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "landingzones" {
  name                       = local.mg_landingzones
  display_name               = "Flagship — Landing Zones"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "prod" {
  name                       = local.mg_prod
  display_name               = "Flagship — Prod"
  parent_management_group_id = azurerm_management_group.landingzones.id

  # The credit subscription is placed here — this is where the workload spokes live.
  subscription_ids = [data.azurerm_subscription.current.subscription_id]
}

resource "azurerm_management_group" "dev" {
  name                       = local.mg_dev
  display_name               = "Flagship — Dev"
  parent_management_group_id = azurerm_management_group.landingzones.id
  # No subscription_ids: dev shares the same sub but logical separation lives at
  # the resource group + tag level. At enterprise scale this MG would hold a
  # dedicated dev subscription.
}
