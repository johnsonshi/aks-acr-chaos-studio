#!/usr/bin/env bash
# 40 — bootstrap the TEST registry so experiments have something to pull:
#  - import a small always-running test image (samples/pause) that also works for crane pulls
#  - enable anonymous pull (simplifies the D1 pull-storm; test registry only)
#  - create two repository-scoped tokens = two identities for D2 tenant fairness
set -euo pipefail

ACR_NAME="${ACR_NAME:?set ACR_NAME (registry name)}"
NAMESPACE="${NAMESPACE:-chaos-pullers}"
TEST_IMAGE="${TEST_IMAGE:-samples/pause:3.9}"

echo ">> Importing ${TEST_IMAGE} from MCR ..."
az acr import -n "$ACR_NAME" --source mcr.microsoft.com/oss/kubernetes/pause:3.9 --image "$TEST_IMAGE" --force

echo ">> Enabling anonymous pull (TEST registry only) ..."
az acr update -n "$ACR_NAME" --anonymous-pull-enabled true -o none

echo ">> Creating two identities (tokens) for the tenant-fairness test ..."
create_token_secret() {
  local token="$1" secret="$2"
  local pass
  pass=$(az acr token create -n "$token" -r "$ACR_NAME" \
      --repository "samples/pause" content/read metadata/read \
      --query "credentials.passwords[0].value" -o tsv 2>/dev/null || true)
  if [ -z "$pass" ]; then
    # token may already exist; regenerate a password
    pass=$(az acr token credential generate -n "$token" -r "$ACR_NAME" \
        --password1 --query "passwords[0].value" -o tsv)
  fi
  if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" create secret generic "$secret" \
      --from-literal=user="$token" --from-literal=pass="$pass" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "   secret/$secret ready in ns/$NAMESPACE"
  else
    echo "   (namespace $NAMESPACE not found yet — run scripts/10-setup-chaos-mesh.sh first)"
  fi
}
create_token_secret tenantA acr-token-a
create_token_secret tenantB acr-token-b

echo ">> Registry bootstrap complete."
