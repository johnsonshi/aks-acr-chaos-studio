#!/usr/bin/env bash
# C1a — Global-endpoint geo-failover (ACR-NATIVE action, NOT a Chaos Studio fault).
#
# Global-endpoint failover is server-side (Traffic Manager DNS + health probe), platform-managed,
# with NO customer trigger and is NOT 429-driven. A client-side network block does not trigger it.
# The only safe, self-service way to *exercise* replica exclusion is this ACR-native toggle.
#
# Effect: excludes/restores a geo-replica from GLOBAL endpoint routing. Data keeps syncing
# bidirectionally; re-enable is instant. Regional endpoints keep working while excluded.
# ACR-native action (not an Azure Chaos Studio fault): temporarily exclude/restore a geo-replica.
set -euo pipefail

REGISTRY="${REGISTRY:?set REGISTRY to the registry NAME (not the login server)}"
REPLICA_REGION="${REPLICA_REGION:?set REPLICA_REGION, e.g. eastus}"
ACTION="${1:-status}"   # exclude | restore | status

case "$ACTION" in
  exclude)
    echo ">> Excluding replica '$REPLICA_REGION' from global-endpoint routing..."
    az acr replication update -r "$REGISTRY" -n "$REPLICA_REGION" --global-endpoint-routing false -o table
    echo ">> Expect global-endpoint clients to reroute within ~minutes + DNS TTL (up to ~5 min)."
    ;;
  restore)
    echo ">> Restoring replica '$REPLICA_REGION' to global-endpoint routing..."
    az acr replication update -r "$REGISTRY" -n "$REPLICA_REGION" --global-endpoint-routing true -o table
    ;;
  status)
    az acr replication list -r "$REGISTRY" -o table
    ;;
  *)
    echo "usage: REGISTRY=<name> REPLICA_REGION=<region> $0 [exclude|restore|status]" >&2
    exit 2
    ;;
esac
