#!/usr/bin/env bash
# Run the observability KQL against Log Analytics and save results for the run.
set -euo pipefail

LAW_ID="${LAW_ID:?set LAW_ID (full resource id of the Log Analytics workspace)}"
OUT_DIR="${OUT_DIR:-results/$(date +%Y%m%dT%H%M%SZ)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CUSTOMER_ID=$(az monitor log-analytics workspace show --ids "$LAW_ID" --query customerId -o tsv)
mkdir -p "$OUT_DIR"

for q in sli-pull-success auth-failures throttling-429; do
  echo ">> query: $q"
  az monitor log-analytics query \
    -w "$CUSTOMER_ID" \
    --analytics-query "$(cat "${SCRIPT_DIR}/observability/${q}.kql")" \
    -o table | tee "${OUT_DIR}/${q}.txt"
done

echo ">> Saved results to ${OUT_DIR}"
