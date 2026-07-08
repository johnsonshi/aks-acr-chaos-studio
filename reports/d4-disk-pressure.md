# D4 — acrchaos-d4-disk-pressure

- **Status:** BLOCKED
- **Date (UTC):** 2026-07-07T04:59:14Z
- **Environment:** AKS `1.35` + Premium ACR (region `eastus2`, registry `myregistry.azurecr.io`)
- **Injection mechanism:** Agent-based Chaos Studio Linux disk I/O pressure
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report documents that Linux disk I/O pressure faults require an agent-based Chaos target that is not supported for this AKS-managed node-pool configuration.

## Hypothesis
Injecting disk I/O pressure on an AKS node should expose whether image pull/cache paths and registry-facing workloads degrade but recover after the fault ends.

## Steady-state signal
A healthy Microsoft-Agent target exists on the node VMSS and supports `LinuxDiskIOPressure-1.1`; disk and workload signals degrade during injection and recover after cancel.

## Steps
```bash
cd aks-acr-chaos-studio
source ./.chaos.env
RESOURCE_GROUP=rg-acr-chaos AKS_NAME="$AKS_NAME" LOCATION=eastus2 \
  bash scripts/30-onboard-agent-target.sh 2>&1 | tee reports/onboard.log
sleep 150
NODE_RG=$(az aks show -g rg-acr-chaos -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
VMSS_ID=$(az vmss list -g "$NODE_RG" --query '[0].id' -o tsv)
az rest --method get --url "https://management.azure.com/$VMSS_ID/providers/Microsoft.Chaos/targets/Microsoft-Agent?api-version=2024-01-01" \
  2>&1 | tee reports/agent-target-check.log
```

## Evidence
```
Onboarding failed while enabling the Microsoft-Agent target:
ERROR: Bad Request({"error":{"code":"BadRequest","message":"The property 'TenantId' cannot be null."}})

The follow-up target check after ~2.5 minutes found no agent target:
ERROR: Not Found({"error":{"code":"NotFound","message":"The resource could not be found."}})
```

## Result
BLOCKED — no usable `Microsoft-Agent` target exists, so Linux disk I/O pressure is not supported in this configuration.

## Findings / limitations
Agent-based faults require the Chaos Studio agent VM extension and capability on the node VMSS, which is not supported on AKS-managed node pools. Prefer Kubernetes/service-direct fault mechanisms for AKS client-side ACR experiments.

## Cleanup
No D4 experiment was created or started. UAMI `chaos-agent-uami` remains assigned to the AKS node VMSS; no AKS system resources were deleted.
