#!/usr/bin/env bash
# F3 support — configure an Artifact Cache rule so cached pulls survive an upstream outage.
# After this, block the upstream (MCR / Docker Hub) from the AKS subnet and confirm cached images
# still pull from ACR.
set -euo pipefail

REGISTRY="${REGISTRY:?set REGISTRY (registry name)}"
RULE_NAME="${RULE_NAME:-mcr-hello-world}"
# Cache mcr.microsoft.com/hello-world into <registry>/cache/hello-world by default.
TARGET_REPO="${TARGET_REPO:-cache/hello-world}"
SOURCE_REPO="${SOURCE_REPO:-mcr.microsoft.com/hello-world}"

echo ">> Creating cache rule '$RULE_NAME': $SOURCE_REPO -> $REGISTRY/$TARGET_REPO"
az acr cache create \
  -r "$REGISTRY" \
  -n "$RULE_NAME" \
  -s "$SOURCE_REPO" \
  -t "$TARGET_REPO"

echo ">> Cache rules:"
az acr cache list -r "$REGISTRY" -o table
echo ">> Prime the cache once (pull through ACR), THEN run the F3 upstream-block experiment:"
echo "   docker pull ${REGISTRY}.azurecr.io/${TARGET_REPO}:latest"
