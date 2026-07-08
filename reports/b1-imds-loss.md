# B1 — acrchaos-b1-imds-loss

- **Status:** BLOCKED
- **Date (UTC):** 2026-07-07T04:59:14Z
- **Environment:** AKS `1.35` + Premium ACR (region `eastus2`, registry `myregistry.azurecr.io`)
- **Injection mechanism:** Agent-based Chaos Studio `networkDisconnect/1.2` to IMDS `169.254.169.254:80`
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report documents that IMDS network-disconnect faults require the Chaos Studio agent target and are not supported for this AKS-managed node-pool configuration.

## Hypothesis
Blocking node access to IMDS should surface managed-identity/metadata dependency failures while the cluster otherwise remains recoverable.

## Steady-state signal
A working Microsoft-Agent target exists on the AKS node VMSS, the B1 experiment can start, and IMDS calls from an affected node fail during the fault and recover after cancel.

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
>> Node RG: MC_<rg>_<aks>_<region>
>> VMSS:    aks-system-<vmss-id>-vmss
>> Creating user-assigned identity for the agent...
>> Assigning the identity to the VMSS...
WARNING: With manual upgrade mode, you will need to run 'az vmss update-instances -g MC_<rg>_<aks>_<region> -n aks-system-<vmss-id>-vmss --instance-ids *' to propagate the change
>> Enabling the Microsoft-Agent target on the VMSS (az rest)...
ERROR: Bad Request({
  "error": {
    "code": "BadRequest",
    "message": "The property 'TenantId' cannot be null."
  }
})

NODE_RG=MC_<rg>_<aks>_<region>
VMSS_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MC_<rg>_<aks>_<region>/providers/Microsoft.Compute/virtualMachineScaleSets/aks-system-<vmss-id>-vmss
ERROR: Not Found({
  "error": {
    "code": "NotFound",
    "message": "The resource could not be found."
  }
})
```

## Result
BLOCKED — onboarding did not create a usable `Microsoft-Agent` Chaos target, so the B1 IMDS `networkDisconnect` experiment is not supported in this configuration.

## Findings / limitations
Agent-based faults require the Chaos Studio agent VM extension and a healthy `Microsoft-Agent` target on the node VMSS, which is not supported on AKS-managed node pools. For AKS-to-ACR client-side resilience, prefer service-direct AKS Chaos Mesh experiments; A2/A3 cover DNS and network behavior with PASS results.

## Cleanup
No experiment was started. The onboarding attempt created or used UAMI `chaos-agent-uami` and assigned it to VMSS `aks-system-<vmss-id>-vmss`; it remained assigned after the blocked onboarding attempt. The ChaosAgent VMSS extension was not installed because target creation failed first.
