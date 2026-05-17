################################################################################
# Environment-scoped federated credentials
#
# Day 2 taught us: when a GitHub Actions job declares `environment:`, the OIDC
# token subject changes from `ref:refs/heads/...` to `environment:<name>`.
# Pre-creating env-scoped credentials avoids the AADSTS700213 error.
#
# Naming convention: <repo>-apply (e.g., platform-apply, landing-zone-apply).
# Add to this file whenever a new environment is added to a caller workflow.
################################################################################

resource "azurerm_federated_identity_credential" "env_apply" {
  for_each = {
    platform = {
      identity_key = "platform"
      env_name     = "platform-apply"
      repo         = "orealvic/flagship-platform"
    }
    landing = {
      identity_key = "landing"
      env_name     = "landing-zone-apply"
      repo         = "orealvic/flagship-landing-zone"
    }
    # app and ai environments will be added on Days 4 and 5
  }

  name                = "gh-${each.value.identity_key}-env-${each.value.env_name}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  parent_id           = azurerm_user_assigned_identity.github_oidc[each.value.identity_key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${each.value.repo}:environment:${each.value.env_name}"
}
