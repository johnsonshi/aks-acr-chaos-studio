#!/usr/bin/env bash
# Baseline + steady-state reachability probes. Run BEFORE, DURING, and AFTER each experiment.
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:?set RESOURCE_GROUP}"
AKS_NAME="${AKS_NAME:?set AKS_NAME}"
ACR_NAME="${ACR_NAME:?set ACR_NAME (registry name)}"

echo "==== az aks check-acr (AKS -> ACR reachability) ===="
az aks check-acr -g "$RESOURCE_GROUP" -n "$AKS_NAME" --acr "${ACR_NAME}.azurecr.io" || true

echo
echo "==== az acr check-health (DNS / challenge / refresh token / access token) ===="
az acr check-health -n "$ACR_NAME" --yes || true
