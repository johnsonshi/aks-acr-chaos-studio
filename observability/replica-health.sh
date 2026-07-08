#!/usr/bin/env bash
# Confirm a geo-failover (C1a): replicas experiencing issues show a status other than 'online'.
# Confirm a geo-failover: replicas with issues show a status other than 'online'.
set -euo pipefail
REGISTRY="${REGISTRY:?set REGISTRY (registry name)}"
az acr replication list -r "$REGISTRY" -o table
