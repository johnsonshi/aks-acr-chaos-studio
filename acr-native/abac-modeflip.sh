#!/usr/bin/env bash
# B2 (ABAC tie-in) — Flip the registry role-assignment mode (ACR-NATIVE action, NOT a Chaos fault).
#
# Tokens minted while the registry is RBAC-only are invalidated after flipping to ABAC; clients get
# 401 until they refresh their cached credential AFTER the flip. This script flips the mode; pair it
# with a forced kubelet credential refresh to reproduce the invalidation, then verify recovery.
# ACR-native action (not an Azure Chaos Studio fault): az acr update --role-assignment-mode
set -euo pipefail

REGISTRY="${REGISTRY:?set REGISTRY (registry name)}"
RESOURCE_GROUP="${RESOURCE_GROUP:?set RESOURCE_GROUP}"
MODE="${1:?usage: $0 <rbac-abac|rbac>   # rbac-abac = ABAC on; rbac = legacy RBAC-only}"

echo ">> Current mode:"
az acr show -n "$REGISTRY" -g "$RESOURCE_GROUP" --query "roleAssignmentMode" -o tsv || true

echo ">> Setting role-assignment-mode = $MODE ..."
az acr update -n "$REGISTRY" -g "$RESOURCE_GROUP" --role-assignment-mode "$MODE" -o table

cat <<'NOTE'
>> Reminder: ABAC-enabled registries IGNORE AcrPull/AcrPush/AcrDelete.
   Assign "Container Registry Repository Reader/Writer/Contributor" instead.
>> To reproduce the credential-cache invalidation on AKS: force kubelet to refresh its cached ACR
   credential AFTER this flip (e.g., restart kubelet / recreate the pod), NOT before.
NOTE
