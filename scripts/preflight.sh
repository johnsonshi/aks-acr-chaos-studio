#!/usr/bin/env bash
# Preflight: is the environment ready to actually RUN experiments? Prints PASS/WARN/FAIL, never exits nonzero.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass(){ echo "  PASS  $*"; }
warn(){ echo "  WARN  $*"; }
fail(){ echo "  FAIL  $*"; }

echo "== Azure =="
if az account show >/dev/null 2>&1; then pass "az logged in ($(az account show --query name -o tsv))"; else fail "not logged in (az login)"; fi
STATE=$(az provider show --namespace Microsoft.Chaos --query registrationState -o tsv 2>/dev/null || echo Unknown)
[ "$STATE" = "Registered" ] && pass "Microsoft.Chaos registered" || warn "Microsoft.Chaos = $STATE (run scripts/00-prereqs.sh)"
az extension show --name chaos >/dev/null 2>&1 && pass "chaos CLI extension present" || warn "chaos extension missing (run scripts/00-prereqs.sh)"

echo "== Deployment state =="
if [ -f "${ROOT}/.chaos.env" ]; then
  pass ".chaos.env present"; set -a; . "${ROOT}/.chaos.env"; set +a
  echo "        ACR=${ACR_LOGIN:-?} AKS=${AKS_NAME:-?} NSG=${NSG_NAME:-?}"
else
  warn ".chaos.env missing (run: make up)"
fi

echo "== Cluster =="
if kubectl get nodes >/dev/null 2>&1; then
  pass "kubectl reachable ($(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ') nodes)"
  kubectl -n chaos-testing get deploy chaos-controller-manager >/dev/null 2>&1 && pass "Chaos Mesh installed" || warn "Chaos Mesh not installed (scripts/10-setup-chaos-mesh.sh) — needed for A2/A3"
  kubectl get ns chaos-pullers >/dev/null 2>&1 && pass "namespace chaos-pullers exists" || warn "namespace chaos-pullers missing"
else
  warn "kubectl not reachable (make prep / az aks get-credentials)"
fi

echo "== Registry =="
if [ -n "${ACR_NAME:-}" ]; then
  az acr repository show -n "$ACR_NAME" --image samples/pause:3.9 >/dev/null 2>&1 \
    && pass "test image samples/pause present" || warn "test image missing (scripts/40-prep-registry.sh)"
fi

echo "== Experiments =="
if [ -n "${RG:-}" ]; then
  az chaos experiment list -g "$RG" --query "[].name" -o tsv 2>/dev/null | sed 's/^/  found /' || warn "no experiments (make chaos)"
else
  warn "set RG=<rg> to list experiments"
fi
echo "Done."
