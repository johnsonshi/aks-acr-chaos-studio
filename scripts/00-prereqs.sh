#!/usr/bin/env bash
# 00 — one-time prerequisites for running Chaos Studio experiments.
set -euo pipefail

echo ">> Registering the Microsoft.Chaos resource provider (idempotent)..."
az provider register --namespace Microsoft.Chaos

echo ">> Installing/updating the 'chaos' az CLI extension..."
az extension add --name chaos --upgrade --yes 2>/dev/null || az extension add --name chaos --yes

echo ">> Versions:"
az version --query '"azure-cli"' -o tsv
az extension show --name chaos --query version -o tsv
echo ">> Done. Provider registration can take a few minutes:"
az provider show --namespace Microsoft.Chaos --query registrationState -o tsv
