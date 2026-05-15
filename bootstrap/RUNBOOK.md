# Bootstrap Runbook

> **One-time setup. Run this once from your laptop. Every subsequent Terraform run goes through GitHub Actions OIDC with zero secrets.**

## Prerequisites

```bash
# Verify versions
az --version             # >= 2.60
terraform --version      # >= 1.9
gh --version             # >= 2.50 (optional, for repo creation)
```

If anything is missing:

```bash
# Azure CLI (Ubuntu)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Terraform (Ubuntu)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# GitHub CLI
sudo apt install gh
```

## Step 1 — Authenticate

```bash
az login
az account set --subscription 581d2bc0-046e-4a3b-b753-ed9977729366
az account show     # confirm you're on the right sub
```

## Step 2 — Confirm spending limit is ON

```bash
az consumption budget list --query "[].{Name:name, Amount:amount, Spent:currentSpend.amount}" -o table
```

Then in the portal: **Subscriptions → your sub → Properties → Spending limit**. Must say "On". Screenshot it for `flagship-docs/portfolio-evidence/`.

## Step 3 — Prepare tfvars

```bash
cd flagship-platform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set your real email address. subscription_id is already filled.
```

## Step 4 — First apply (local state — this is intentional)

```bash
terraform init
terraform plan -out=bootstrap.tfplan
# Review the plan carefully. ~25 resources expected.
terraform apply bootstrap.tfplan
```

Expected runtime: 2–3 minutes. No app resources yet — just the storage account, OIDC identities, RBAC, and the budget alert.

## Step 5 — Migrate state to Azure

After apply, capture the storage account name:

```bash
TFSTATE_SA=$(terraform output -raw tfstate_storage_account_name)
TFSTATE_RG=$(terraform output -raw tfstate_resource_group_name)
echo "State storage: $TFSTATE_SA in $TFSTATE_RG"
```

Add the backend block to `main.tf` (or create `backend.tf`):

```hcl
terraform {
  backend "azurerm" {
    use_azuread_auth     = true
    # The rest is supplied at init-time
  }
}
```

Then re-init with the migration flag:

```bash
terraform init -migrate-state \
  -backend-config="resource_group_name=$TFSTATE_RG" \
  -backend-config="storage_account_name=$TFSTATE_SA" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=bootstrap.tfstate"
```

Confirm yes when prompted. After this, `terraform.tfstate` no longer exists locally.

## Step 6 — Capture outputs for GitHub

```bash
terraform output -raw next_steps
```

This prints the exact GitHub Variables to set on each repo. Save the output to a notes file (NOT in the repo).

## Step 7 — Create the GitHub repos

```bash
# Use gh CLI or do it via the web UI
for repo in flagship-platform flagship-landing-zone flagship-app flagship-ai flagship-docs flagship-actions; do
  gh repo create "orealvic/$repo" --public --description "Flagship Azure landing zone — $repo"
done
```

For each repo, set Repository Variables via **Settings → Secrets and variables → Actions → Variables**. Use the values from Step 6.

Then enable security features per repo:

```bash
for repo in flagship-platform flagship-landing-zone flagship-app flagship-ai flagship-docs flagship-actions; do
  gh api -X PATCH "/repos/orealvic/$repo" -f security_and_analysis.secret_scanning.status=enabled
  gh api -X PATCH "/repos/orealvic/$repo" -f security_and_analysis.secret_scanning_push_protection.status=enabled
done
```

## Step 8 — Push the bootstrap code

```bash
cd flagship-platform
git init
git add .
git commit -m "feat: initial bootstrap module — state backend + OIDC + budgets"
git branch -M main
git remote add origin git@github.com:orealvic/flagship-platform.git
git push -u origin main
```

## Step 9 — Verify the safety net

In the portal:

1. **Cost Management → Budgets** — confirm `bud-flagship` exists with three thresholds (50/80/100%)
2. **Resource groups → rg-flagship-platform-bootstrap** — confirm storage account, 4 managed identities, 16 federated credentials, 1 action group
3. **Trigger a test alert**: Cost Management → Budgets → ⋯ → Send test alert

## You're done with Day 1 bootstrap.

What you have now:
- ✅ Hardened state backend with versioning, soft-delete, AAD auth only
- ✅ Four OIDC identities federated to four GitHub repos (main + PR contexts)
- ✅ Budget tripwires at $100, $160, $200
- ✅ All RBAC pre-wired so future pipelines have what they need
- ✅ Zero long-lived secrets anywhere
- ✅ Public repo with hardened `.gitignore` and secret scanning

What's next (Day 2):
- Management group hierarchy
- Azure Policy: tag enforcement, allowed locations, denied SKUs
- Hub VNet
- Log Analytics workspace
