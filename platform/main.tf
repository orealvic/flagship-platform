################################################################################
# Platform stack
#
# Deploys the shared platform layer:
#   - Management group hierarchy (tg-flagship root, platform + landingzones,
#     prod and dev under landingzones)
#   - Subscription placement under landingzones
#   - Azure Policy: tag enforcement, allowed locations, denied SKUs
#   - Log Analytics workspace (1GB/day cap, free tier guardrail)
#   - Hub VNet + subnets (no Bastion/VPN yet — those come on-demand later)
#   - Private DNS zones for the services we'll add later
#
# Runs from GitHub Actions via OIDC. State key: platform.tfstate
################################################################################

terraform {
  required_version = ">= 1.9.0"

  backend "azurerm" {
    use_azuread_auth = true
    # Other backend config supplied at init time by the reusable workflow.
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

locals {
  # The 5-tag taxonomy. Applied to every taggable resource in this stack.
  common_tags = {
    environment  = "platform"
    region       = var.location
    cost-center  = "flagship-portfolio"
    managed-by   = "terraform"
    service-tier = "shared"
  }

  # Naming convention: <kind>-<project>-<role>-<region-short>
  region_short = "cac"  # Canada Central

  # MG IDs (group ID is what Azure uses internally; display_name is for humans).
  mg_root         = "tg-flagship"
  mg_platform     = "tg-flagship-platform"
  mg_landingzones = "tg-flagship-landingzones"
  mg_prod         = "tg-flagship-prod"
  mg_dev          = "tg-flagship-dev"
}

# Trigger fresh apply after CI/CD env fix

# Trigger after YAML indent fix
