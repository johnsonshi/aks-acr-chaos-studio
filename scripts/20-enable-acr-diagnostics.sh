#!/usr/bin/env bash
# 20 — enable ACR diagnostic logs -> Log Analytics (already done by infra Bicep; use for existing registries).
set -euo pipefail

ACR_ID="${ACR_ID:?set ACR_ID (full resource id of the registry)}"
LAW_ID="${LAW_ID:?set LAW_ID (full resource id of the Log Analytics workspace)}"

az monitor diagnostic-settings create \
  --name acr-to-la \
  --resource "$ACR_ID" \
  --workspace "$LAW_ID" \
  --logs '[{"category":"ContainerRegistryRepositoryEvents","enabled":true},{"category":"ContainerRegistryLoginEvents","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  -o table
