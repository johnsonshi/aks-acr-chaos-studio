#!/usr/bin/env bash
# 50 — full teardown: delete the resource group, then purge the soft-deleted CMK key vault so its
# name can be reused. Purge-protected vaults CANNOT be purged until the retention window elapses;
# in that case, use a different PREFIX or RG for the next CMK cycle.
set -euo pipefail

RG="${RG:?set RG}"
LOCATION="${LOCATION:-eastus}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KV_NAME=""
if [ -f "${ROOT}/.chaos.env" ]; then
  # shellcheck disable=SC1091
  set -a; . "${ROOT}/.chaos.env"; set +a
  KV_NAME="${KV_NAME:-}"
fi

echo ">> Deleting resource group ${RG} (this can take several minutes)..."
az group delete -n "$RG" --yes

if [ -n "$KV_NAME" ] && [ "$KV_NAME" != "null" ]; then
  echo ">> Purging soft-deleted key vault ${KV_NAME} ..."
  if az keyvault purge -n "$KV_NAME" -l "$LOCATION" 2>/dev/null; then
    echo "   purged."
  else
    echo "   WARNING: could not purge ${KV_NAME} (purge protection reserves the name until the"
    echo "   soft-delete retention elapses). For an immediate CMK re-run, use a different PREFIX or RG."
  fi
fi

rm -f "${ROOT}/.chaos.env" "${ROOT}/.deploy-outputs.json"
echo ">> Teardown complete."
