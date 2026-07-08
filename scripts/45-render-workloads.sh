#!/usr/bin/env bash
# 45 — render workloads/*.yaml (which use ${REGISTRY}) with the real login server, then apply the
# always-on cached workload. Only $REGISTRY is substituted so the in-container $i/$ITERATIONS/etc.
# shell variables are left intact.
set -euo pipefail

REGISTRY="${REGISTRY:?set REGISTRY (registry login server, e.g. myacr.azurecr.io)}"
NAMESPACE="${NAMESPACE:-chaos-pullers}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/workloads/rendered"

mkdir -p "$OUT"
for f in pull-storm-job cached-workload tenant-fairness-a tenant-fairness-b; do
  REGISTRY="$REGISTRY" envsubst '$REGISTRY' < "${ROOT}/workloads/${f}.yaml" > "${OUT}/${f}.yaml"
done
echo ">> Rendered to ${OUT} (REGISTRY=${REGISTRY})"

kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" apply -f "${OUT}/cached-workload.yaml"
kubectl -n "$NAMESPACE" apply -f "${ROOT}/workloads/dns-probe.yaml"
kubectl -n "$NAMESPACE" apply -f "${ROOT}/workloads/net-probe.yaml"
echo ">> Applied cached-workload + dns-probe + net-probe (exec into them to observe A2/A3)."
echo ">> Applied cached-workload. For load tests, apply when running:"
echo "   kubectl -n ${NAMESPACE} apply -f ${OUT}/pull-storm-job.yaml         # D1/D3"
echo "   kubectl -n ${NAMESPACE} apply -f ${OUT}/tenant-fairness-a.yaml -f ${OUT}/tenant-fairness-b.yaml  # D2"
