#!/usr/bin/env bash
# One-time setup so the chaos-gameday GitHub Actions workflow can log in via OIDC (no stored secrets).
# Creates an Entra app + federated credential for the repo, grants Contributor on the RG (enough to
# START/CANCEL experiments and query Log Analytics), and sets the repo secrets + variables.
#
# NOTE: deploying infra/chaos.bicep (which CREATES role assignments) must be done by an Owner locally,
# not by this CI identity. CI only starts/stops experiments + collects SLIs.
#
# Prereqs: gh authenticated to the repo, az logged in, and a deployed stack (.chaos.env present).
set -euo pipefail

GH_REPO="${GH_REPO:?set GH_REPO=owner/name}"
RG="${RG:?set RG (the resource group holding the experiments)}"
SUB="$(az account show --query id -o tsv)"
TENANT="$(az account show --query tenantId -o tsv)"
APP_NAME="${APP_NAME:-chaos-gameday-$(echo "$GH_REPO" | tr '/' '-')}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ">> Creating/looking up Entra app '$APP_NAME' ..."
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
[ -z "$APP_ID" ] && APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" >/dev/null
SP_OID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

echo ">> Federated credential for repo:$GH_REPO (main branch) ..."
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\":\"gh-main\",
  \"issuer\":\"https://token.actions.githubusercontent.com\",
  \"subject\":\"repo:${GH_REPO}:ref:refs/heads/main\",
  \"audiences\":[\"api://AzureADTokenExchange\"]
}" 2>/dev/null || echo "   (federated credential may already exist)"

echo ">> Granting Contributor on RG $RG ..."
az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role Contributor --scope "/subscriptions/${SUB}/resourceGroups/${RG}" -o none 2>/dev/null || true

echo ">> Setting GitHub secrets + variables on $GH_REPO ..."
gh secret set AZURE_CLIENT_ID       -R "$GH_REPO" -b "$APP_ID"
gh secret set AZURE_TENANT_ID       -R "$GH_REPO" -b "$TENANT"
gh secret set AZURE_SUBSCRIPTION_ID -R "$GH_REPO" -b "$SUB"
if [ -f "${ROOT}/.chaos.env" ]; then
  set -a; . "${ROOT}/.chaos.env"; set +a
  gh variable set ACR_NAME -R "$GH_REPO" -b "${ACR_NAME:-}"
  gh variable set AKS_NAME -R "$GH_REPO" -b "${AKS_NAME:-}"
  gh variable set LAW_ID   -R "$GH_REPO" -b "${LAW_ID:-}"
fi
echo ">> Done. The chaos-gameday workflow can now log in via OIDC."
