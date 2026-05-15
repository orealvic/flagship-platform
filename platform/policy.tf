################################################################################
# Azure Policy — the guardrails
#
# Three custom policies + a set definition (initiative) assigned at the
# tg-flagship root MG. Inheritance carries the assignment to every child MG
# and the subscription beneath them.
#
#   1. require-tag — denies create/update of resources missing required tags
#   2. allowed-locations — denies resources outside canadacentral
#   3. denied-skus — denies expensive SKUs we don't want accidentally deployed
#
# Note: tag-enforcement uses DENY effect for new resources. Existing untagged
# resources from Day 1 (created before the policy) are exempted via the
# `notScope` on the assignment. We could also use `Modify` effect to auto-tag,
# but `Deny` is cleaner for a portfolio project — it shows the strict pattern.
################################################################################

# ─── Policy 1: require-tag (one per required tag) ──────────────────────────
# Built-in policy: Require a tag on resources
# id: /providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99

resource "azurerm_management_group_policy_assignment" "require_environment_tag" {
  name                 = "require-tag-environment"
  display_name         = "Require 'environment' tag on resources"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"

  parameters = jsonencode({
    tagName = { value = "environment" }
  })

  # Exempt the bootstrap RG so we don't break Day 1 resources retroactively.
  not_scopes = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/rg-flagship-platform-bootstrap"
  ]
}

resource "azurerm_management_group_policy_assignment" "require_cost_center_tag" {
  name                 = "require-tag-cost-center"
  display_name         = "Require 'cost-center' tag on resources"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"

  parameters = jsonencode({
    tagName = { value = "cost-center" }
  })

  not_scopes = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/rg-flagship-platform-bootstrap"
  ]
}

resource "azurerm_management_group_policy_assignment" "require_managed_by_tag" {
  name                 = "require-tag-managed-by"
  display_name         = "Require 'managed-by' tag on resources"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"

  parameters = jsonencode({
    tagName = { value = "managed-by" }
  })

  not_scopes = [
    "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/rg-flagship-platform-bootstrap"
  ]
}

# ─── Policy 2: allowed-locations ───────────────────────────────────────────
# Built-in: Allowed locations
# id: /providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c

resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Allowed locations — Canada Central only"
  description          = "Restrict all flagship resources to canadacentral to control cost and meet data residency"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = ["canadacentral", "global"] # global needed for things like MGs, action groups
    }
  })
}

# ─── Policy 3: denied SKUs ─────────────────────────────────────────────────
# Custom policy: prevent expensive VM and App Service SKUs from being deployed.
# Resource type is `azurerm_policy_definition` with `management_group_id` set —
# NOT a separate "azurerm_management_group_policy_definition" resource type.

resource "azurerm_policy_definition" "deny_expensive_skus" {
  name                = "deny-expensive-skus"
  policy_type         = "Custom"
  mode                = "Indexed"
  display_name        = "Deny expensive VM and App Service SKUs"
  description         = "Prevent accidental deployment of expensive SKUs that would burn the $200 credit"
  management_group_id = azurerm_management_group.root.id

  policy_rule = jsonencode({
    if = {
      anyOf = [
        {
          allOf = [
            { field = "type", equals = "Microsoft.Compute/virtualMachines" },
            {
              field = "Microsoft.Compute/virtualMachines/sku.name",
              in = [
                "Standard_M64ms", "Standard_M128ms", "Standard_M208ms_v2",
                "Standard_D64s_v3", "Standard_E64s_v3", "Standard_F72s_v2",
                "Standard_GS5", "Standard_DS15_v2"
              ]
            }
          ]
        },
        {
          allOf = [
            { field = "type", equals = "Microsoft.Web/serverfarms" },
            {
              field = "Microsoft.Web/serverfarms/sku.tier",
              in    = ["PremiumV3", "Isolated", "IsolatedV2"]
            }
          ]
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "deny_expensive_skus" {
  name                 = "deny-expensive-skus"
  display_name         = "Deny expensive SKUs"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = azurerm_policy_definition.deny_expensive_skus.id
}
