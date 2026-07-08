#!/usr/bin/env bash
# 10 — install Chaos Mesh on the AKS cluster (required for A2/A3 service-direct faults).
# Mirrors the Chaos Studio AKS tutorial. DNS Chaos (A2) additionally needs the chaos-dns service,
# which the chaos-mesh chart installs when dnsServer.create=true.
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:?set RESOURCE_GROUP}"
AKS_NAME="${AKS_NAME:?set AKS_NAME}"
CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.7.0}"

echo ">> Getting AKS credentials for $AKS_NAME ..."
az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_NAME" --overwrite-existing

echo ">> Installing Chaos Mesh $CHAOS_MESH_VERSION via Helm ..."
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
kubectl create ns chaos-testing --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-testing \
  --version "$CHAOS_MESH_VERSION" \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dnsServer.create=true

echo ">> Creating the pull-test namespace used by workloads/*.yaml ..."
kubectl create ns chaos-pullers --dry-run=client -o yaml | kubectl apply -f -

echo ">> Waiting for Chaos Mesh pods..."
kubectl -n chaos-testing rollout status deploy/chaos-controller-manager --timeout=180s
kubectl -n chaos-testing get pods
