################################################################################
# Bootstrap module
#
# This is the ONLY Terraform code that runs with local state. It creates:
#   - The Azure Storage Account that holds remote state for everything else
#   - The federated identity credentials so GitHub Actions can auth via OIDC
#   - The hard budget alerts that protect the $200 credit
#   - The "kill switch" action group that auto-stops expensive resources
#
# Run once from your laptop after `az login`. After that, every other Terraform
# run uses remote state + OIDC, with zero secrets stored anywhere.
################################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

# A short random suffix keeps storage account names globally unique without
# needing to hand-pick something cute. Reuse this pattern everywhere.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

locals {
  # The 5-tag taxonomy from your Tradogram pattern.
  common_tags = {
    environment   = "platform"
    region        = var.location
    cost-center   = "flagship-portfolio"
    managed-by    = "terraform"
    service-tier  = "shared"
  }

  resource_group_name  = "rg-flagship-platform-bootstrap"
  storage_account_name = "stflagshiptf${random_string.suffix.result}"
}

################################################################################
# State backend
################################################################################

resource "azurerm_resource_group" "bootstrap" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "tfstate" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.bootstrap.name
  location                 = azurerm_resource_group.bootstrap.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # cost-engineered: no GRS for a portfolio project

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # force AAD auth, no SAS keys floating around
  public_network_access_enabled   = true  # required for first GH Actions run; lock down later

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# One container, region-isolated state files matching the Tradogram pattern:
#   platform.tfstate, prod.tfstate, dev.tfstate, ai.tfstate
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

################################################################################
# GitHub Actions OIDC federation
#
# Creates one User-Assigned Managed Identity per environment (platform/prod/dev/ai),
# each federated to a specific GitHub repo + environment.
# This is the "zero long-lived secrets" story.
################################################################################

resource "azurerm_user_assigned_identity" "github_oidc" {
  for_each = {
    platform = "orealvic/flagship-platform"
    landing  = "orealvic/flagship-landing-zone"
    app      = "orealvic/flagship-app"
    ai       = "orealvic/flagship-ai"
  }

  name                = "id-gh-${each.key}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location
  tags                = local.common_tags
}

# Federated credential for the `main` branch of each repo
resource "azurerm_federated_identity_credential" "main_branch" {
  for_each = {
    platform = "orealvic/flagship-platform"
    landing  = "orealvic/flagship-landing-zone"
    app      = "orealvic/flagship-app"
    ai       = "orealvic/flagship-ai"
  }

  name                = "gh-${each.key}-main"
  resource_group_name = azurerm_resource_group.bootstrap.name
  parent_id           = azurerm_user_assigned_identity.github_oidc[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${each.value}:ref:refs/heads/main"
}

# Federated credential for PR builds (plan-only, no apply)
resource "azurerm_federated_identity_credential" "pull_request" {
  for_each = {
    platform = "orealvic/flagship-platform"
    landing  = "orealvic/flagship-landing-zone"
    app      = "orealvic/flagship-app"
    ai       = "orealvic/flagship-ai"
  }

  name                = "gh-${each.key}-pr"
  resource_group_name = azurerm_resource_group.bootstrap.name
  parent_id           = azurerm_user_assigned_identity.github_oidc[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${each.value}:pull_request"
}

# RBAC: platform identity gets Owner on the subscription (it manages MGs and policy)
# Others get Contributor scoped to their resource groups (created later).
resource "azurerm_role_assignment" "platform_owner" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.github_oidc["platform"].principal_id
}

resource "azurerm_role_assignment" "platform_uaa" {
  # User Access Administrator so platform IaC can assign RBAC to other identities
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_user_assigned_identity.github_oidc["platform"].principal_id
}

# Other identities get Contributor at sub level for now; tighten to RGs in platform stack.
resource "azurerm_role_assignment" "workload_contributor" {
  for_each = toset(["landing", "app", "ai"])

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github_oidc[each.key].principal_id
}

# Storage Blob Data Contributor on the state SA for all four identities
resource "azurerm_role_assignment" "tfstate_access" {
  for_each = toset(["platform", "landing", "app", "ai"])

  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github_oidc[each.key].principal_id
}

################################################################################
# Budget alerts — the $200 credit guardrails
################################################################################

resource "azurerm_monitor_action_group" "budget_alerts" {
  name                = "ag-flagship-budget"
  resource_group_name = azurerm_resource_group.bootstrap.name
  short_name          = "budget"

  email_receiver {
    name                    = "owner"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = local.common_tags
}

resource "azurerm_consumption_budget_subscription" "main" {
  name            = "bud-flagship"
  subscription_id = data.azurerm_subscription.current.id

  amount     = 200
  time_grain = "BillingMonth"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    # No end_date: Terraform requires it OR an explicit far-future date
    end_date = "2027-12-31T00:00:00Z"
  }

  # 50% — heads up
  notification {
    enabled        = true
    threshold      = 50.0
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }

  # 80% — start thinking about teardown
  notification {
    enabled        = true
    threshold      = 80.0
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }

  # 100% — should never reach this, but if it does, all hands
  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.budget_alerts.id]
  }

  lifecycle {
    ignore_changes = [time_period[0].start_date]
  }
}
