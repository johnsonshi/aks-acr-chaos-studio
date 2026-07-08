#!/usr/bin/env bash
# 30 — onboard the AKS node-pool VMSS as an agent-based Chaos target (for B1 IMDS block, node pressure).
#
# Agent-based faults run INSIDE the node (host tc/firewall), so they can do what NSG can't
# (e.g. block IMDS 169.254.169.254). This requires the AzureChaosAgent extension on the VMSS
# that lives in the AKS *node* resource group.
#
# This is the fiddliest onboarding in Chaos Studio and is version-sensitive. Treat this as a
# guided helper. Agent-based onboarding is version-sensitive and is not supported on
# AKS-managed node pools; prefer service-direct AKS Chaos Mesh faults.
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:?set RESOURCE_GROUP (cluster RG)}"
AKS_NAME="${AKS_NAME:?set AKS_NAME}"
LOCATION="${LOCATION:?set LOCATION}"
UAMI_NAME="${UAMI_NAME:-chaos-agent-uami}"

NODE_RG=$(az aks show -g "$RESOURCE_GROUP" -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
VMSS_ID=$(az vmss list -g "$NODE_RG" --query "[0].id" -o tsv)
VMSS_NAME=$(az vmss list -g "$NODE_RG" --query "[0].name" -o tsv)
echo ">> Node RG: $NODE_RG"
echo ">> VMSS:    $VMSS_NAME"

echo ">> Creating user-assigned identity for the agent..."
UAMI_ID=$(az identity create -g "$RESOURCE_GROUP" -n "$UAMI_NAME" --query id -o tsv)
UAMI_CLIENT_ID=$(az identity show --ids "$UAMI_ID" --query clientId -o tsv)

echo ">> Assigning the identity to the VMSS..."
az vmss identity assign -g "$NODE_RG" -n "$VMSS_NAME" --identities "$UAMI_ID"

echo ">> Enabling the Microsoft-Agent target on the VMSS (az rest)..."
API="2024-01-01"
az rest --method put \
  --url "https://management.azure.com${VMSS_ID}/providers/Microsoft.Chaos/targets/Microsoft-Agent?api-version=${API}" \
  --body "{\"properties\":{\"identities\":[{\"type\":\"AzureManagedIdentity\",\"clientId\":\"${UAMI_CLIENT_ID}\"}]}}"

for CAP in NetworkDisconnect-1.2 NetworkLatency-1.2 NetworkPacketLoss-1.2 CPUPressure-1.0 PhysicalMemoryPressure-1.0 LinuxDiskIOPressure-1.1; do
  echo ">> capability $CAP"
  az rest --method put \
    --url "https://management.azure.com${VMSS_ID}/providers/Microsoft.Chaos/targets/Microsoft-Agent/capabilities/${CAP}?api-version=${API}" \
    --body "{}" >/dev/null
done

echo ">> Installing the AzureChaosAgent VMSS extension..."
AGENT_PROFILE_ID=$(az rest --method get \
  --url "https://management.azure.com${VMSS_ID}/providers/Microsoft.Chaos/targets/Microsoft-Agent?api-version=${API}" \
  --query properties.agentProfileId -o tsv)
az vmss extension set \
  -g "$NODE_RG" --vmss-name "$VMSS_NAME" \
  --name ChaosAgent --publisher Microsoft.Azure.Chaos \
  --version 1.0 \
  --settings "{\"profile\":\"${AGENT_PROFILE_ID}\",\"auth.msi.clientid\":\"${UAMI_CLIENT_ID}\"}"
az vmss update-instances -g "$NODE_RG" -n "$VMSS_NAME" --instance-ids '*'

echo ">> Agent target id (use in experiment selectors):"
echo "${VMSS_ID}/providers/Microsoft.Chaos/targets/Microsoft-Agent"
