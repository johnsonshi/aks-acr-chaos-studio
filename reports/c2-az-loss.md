# C2 — AKS availability-zone loss

- **Status:** BLOCKED
- **Date (UTC):** 2026-07-07T04:55:08Z
- **Environment:** AKS `acrchaos-aks` + Premium geo-replicated ACR `myregistry.azurecr.io` (RG `rg-acr-chaos`)
- **Injection mechanism:** Dependency — Chaos Studio VMSS zone shutdown (not currently onboarded)
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report documents that AKS availability-zone loss testing requires zone-pinned node pools and VMSS Chaos onboarding, neither of which is present in the current stack.

## Hypothesis
If one AKS availability zone is lost, pull workloads scheduled on surviving AKS zones should continue pulling from the zone-redundant ACR service.

## Steady-state signal
Before injection, AKS node pools must span zones `1`, `2`, and `3`; pull-test pods must be healthy; during zone shutdown, pods on surviving zones should continue to pull from ACR without broad image-pull failures.

## Steps
```bash
cd aks-acr-chaos-studio
source ./.chaos.env
az aks show -g rg-acr-chaos -n "$AKS_NAME" --query "agentPoolProfiles[].availabilityZones" -o json
```

To run C2 in an environment with the required infrastructure:
```bash
# 1. Deploy AKS into a zone-capable region/SKU with zone-pinned node pools.
make up RG=rg-acr-chaos LOCATION=eastus2 AKS_VM_SIZE=Standard_D4s_v5 AKS_ZONES='["1","2","3"]'
source ./.chaos.env
az aks show -g rg-acr-chaos -n "$AKS_NAME" --query "agentPoolProfiles[].availabilityZones" -o json

# 2. Discover the AKS node VMSS.
NODE_RG=$(az aks show -g rg-acr-chaos -n "$AKS_NAME" --query nodeResourceGroup -o tsv)
VMSS_ID=$(az vmss list -g "$NODE_RG" --query "[0].id" -o tsv)
VMSS_TARGET_ID="$VMSS_ID/providers/Microsoft.Chaos/targets/Microsoft-VirtualMachineScaleSet"

# 3. Onboard the VMSS as a Chaos target and enable shutdown/2.0.
az rest --method put --url "https://management.azure.com${VMSS_TARGET_ID}?api-version=2024-01-01" --body '{"properties":{}}'
az rest --method put --url "https://management.azure.com${VMSS_TARGET_ID}/capabilities/Shutdown-2.0?api-version=2024-01-01" --body '{"properties":{}}'

# 4. Render experiments/c2-vmss-az-shutdown.json with LOCATION and VMSS_TARGET_ID,
#    then create the experiment and grant its managed identity VMSS rights.
#    The experiment uses urn:csci:microsoft:virtualMachineScaleSet:shutdown/2.0
#    with selector filter parameters.zones=["1"].

# 5. Run probes before/during/after the experiment and verify pulls survive on zones 2/3.
```

## Evidence
```
ACR_NAME=myregistry
AKS_NAME=acrchaos-aks
RG=rg-acr-chaos
--- AKS zones ---
[]
```

## Result
BLOCKED — the current stack has no AKS zone pinning (`[]`), so there is no meaningful zone-loss fault to inject.

## Findings / limitations
- The current stack uses `AKS_ZONES=[]` for portability.
- C2 requires: (a) cluster deployed with zones via `make up ... AKS_ZONES='["1","2","3"]'` in a zone-capable region+SKU; (b) the node VMSS onboarded as a `Microsoft-VirtualMachineScaleSet` Chaos target; and (c) the `virtualMachineScaleSet:shutdown/2.0` fault with a zone selector filter, as sketched by `experiments/c2-vmss-az-shutdown.json`.
- ACR is zone-redundant server-side and is not directly injectable here; C2 tests the AKS client side.

## Cleanup
None — read-only verification only; no fault was started and no Azure resources were changed.
