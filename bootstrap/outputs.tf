output "tfstate_storage_account_name" {
  description = "Storage account holding remote Terraform state"
  value       = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  value = azurerm_storage_container.tfstate.name
}

output "tfstate_resource_group_name" {
  value = azurerm_resource_group.bootstrap.name
}

output "github_oidc_client_ids" {
  description = "Client IDs of the GitHub Actions federated identities — set these as GitHub repo variables"
  value = {
    for k, v in azurerm_user_assigned_identity.github_oidc : k => v.client_id
  }
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

output "next_steps" {
  description = "Paste these into each GitHub repo's Variables (Settings → Secrets and variables → Actions → Variables)"
  value = <<-EOT

    # ┌──────────────────────────────────────────────────────────────────────┐
    # │  GitHub Actions Variables (NOT Secrets — these are not sensitive)    │
    # └──────────────────────────────────────────────────────────────────────┘

    Set the following as Repository Variables in EACH repo:

      AZURE_TENANT_ID       = ${data.azurerm_client_config.current.tenant_id}
      AZURE_SUBSCRIPTION_ID = ${data.azurerm_subscription.current.subscription_id}
      TFSTATE_RG            = ${azurerm_resource_group.bootstrap.name}
      TFSTATE_SA            = ${azurerm_storage_account.tfstate.name}
      TFSTATE_CONTAINER     = ${azurerm_storage_container.tfstate.name}

    Then per-repo, set ALSO:

      flagship-platform:       AZURE_CLIENT_ID = ${azurerm_user_assigned_identity.github_oidc["platform"].client_id}
      flagship-landing-zone:   AZURE_CLIENT_ID = ${azurerm_user_assigned_identity.github_oidc["landing"].client_id}
      flagship-app:            AZURE_CLIENT_ID = ${azurerm_user_assigned_identity.github_oidc["app"].client_id}
      flagship-ai:             AZURE_CLIENT_ID = ${azurerm_user_assigned_identity.github_oidc["ai"].client_id}

    No secrets needed. OIDC handles auth.
  EOT
}
