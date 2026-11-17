#!/usr/bin/env bash
# One-time setup, run by the subscription OWNER in Azure Cloud Shell (bash).
#   1. resource group with the standard tags
#   2. an Entra app for GitHub Actions with a federated credential (OIDC, no secret)
#   3. governance.bicep: policies, RBAC (pipeline = Contributor on the RG), API identity, budget
# At the end it prints the values for the GitHub secrets.
#
# Usage:  ./scripts/setup-azure.sh <github-owner/repo> <your-email>
#   e.g.  ./scripts/setup-azure.sh golqmliutenichar/knowledgehub_cicd you@example.com

set -euo pipefail

REPO="${1:?give the GitHub repo as owner/name}"
EMAIL="${2:-}"
RG="KostovRG"
LOCATION="swedencentral"
APP_NAME="KnowledgeHub-GitHubActions"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo ">>> Subscription: $SUBSCRIPTION_ID"

echo ">>> Registering resource providers (the pipeline only has rights on the resource group)"
for ns in Microsoft.Network Microsoft.App Microsoft.ContainerRegistry Microsoft.DBforMySQL \
          Microsoft.OperationalInsights Microsoft.Insights Microsoft.ManagedIdentity \
          Microsoft.PolicyInsights Microsoft.Consumption; do
  az provider register --namespace "$ns" -o none
done

echo ">>> Resource group $RG"
az group create --name "$RG" --location "$LOCATION" \
  --tags Project=KnowledgeHub Environment=Production Owner=IT CostCenter=Library-IT ManagedBy=IaC -o none

echo ">>> Entra app for GitHub Actions"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
fi
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || az ad sp create --id "$APP_ID" --query id -o tsv)

echo ">>> Federated credential for $REPO (branch main)"
EXISTING=$(az ad app federated-credential list --id "$APP_ID" --query "length([?name=='github-main'])" -o tsv)
if [ "$EXISTING" = "0" ]; then
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none
fi

echo ">>> Governance (policies, RBAC, API identity, budget)"
az deployment group create --resource-group "$RG" --name governance \
  --template-file infra/governance.bicep \
  --parameters pipelinePrincipalId="$SP_ID" budgetEmail="$EMAIL" -o none

cat <<EOF

============================================================
Done. Add these in GitHub: Settings > Secrets and variables > Actions

Secrets:
  AZURE_CLIENT_ID        $APP_ID
  AZURE_TENANT_ID        $TENANT_ID
  AZURE_SUBSCRIPTION_ID  $SUBSCRIPTION_ID
  MYSQL_ADMIN_PASSWORD   (choose a strong password)
  VPN_SHARED_KEY         (choose a long random key, same as in pfSense)
  API_KEY                (choose a long random key, same as in the monitor's .env)

Variables:
  ON_PREM_PUBLIC_IP      (public IP where pfSense runs: curl ifconfig.me at home)
  ALERT_EMAIL            ${EMAIL:-(your email)}
============================================================
EOF
