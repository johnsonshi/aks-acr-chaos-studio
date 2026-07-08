# A1 — acrchaos-a1-nsg-block-acr

- **Status:** PARTIAL
- **Date (UTC):** 2026-07-07T03:37:03Z
- **Environment:** AKS `v1.35.5` + ACR `myregistry` (login `myregistry.azurecr.io`, region eastus2)
- **Injection mechanism:** NSG CIDR deny. Azure Chaos Studio `securityRule/1.0` can apply CIDR destinations through `infra/chaos.bicep` parameter `acrDenyCidrs`; it rejects Azure service tags/system tags as destinations.
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that a CIDR-based NSG deny can make ACR unreachable from AKS while non-ACR egress and cached workloads remain healthy; A1 must use CIDR ranges because the Chaos Studio NSG fault rejects Azure service tags/system tags.

## Hypothesis
Blocking outbound HTTPS from AKS nodes to ACR makes uncached/new registry connections unreachable, while unrelated internet egress remains healthy and already-running cached workloads continue running. In the deployed Bicep path, A1 uses the `acrDenyCidrs` parameter; resolve your registry IPs and replace the inert TEST-NET default before running the experiment.

## Steady-state signal
ACR `/v2/` returns HTTP 401 quickly when reachable; Bing returns HTTP 200; cached-app pods remain Running; recovery restores ACR 401.

## Steps

### A1 start Chaos experiment
```bash
az rest --method post --url 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a1-nsg-block-acr/start?api-version=2024-01-01' -o json
```
```

exit_code=0
```

### A1 execution status polling
```
poll 1: PreProcessing
poll 2: Failed
```

### A1 final latest execution status
```bash
az rest --method get --url 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a1-nsg-block-acr/executions?api-version=2024-01-01' -o json | jq -r '.value|sort_by(.properties.startedAt)|last|{name:.name,status:.properties.status,startedAt:.properties.startedAt,stoppedAt:.properties.stoppedAt}'
```
```
{
  "name": "<guid>",
  "status": "Failed",
  "startedAt": "2026-07-07T03:37:05.1183859+00:00",
  "stoppedAt": "2026-07-07T03:37:20.6501254+00:00"
}
exit_code=0
```

### A1 execution error details
```bash
az rest --method post --url 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a1-nsg-block-acr/executions/<guid>/getExecutionDetails?api-version=2024-01-01' -o json | jq -r '[..|objects|select(has("error") and (.error|type=="object"))|.error.message]|unique'
```
```
[
  "Security rule parameter DestinationAddressPrefix for rule with Id /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Network/networkSecurityGroups/acrchaos-aks-nsg/securityRules/ChaosDenyACRFakeRule cannot specify existing VIRTUALNETWORK, INTERNET, AZURELOADBALANCER, '*' or system tags. Unsupported value used: AzureContainerRegistry.\nStatus: 400 (Bad Request)\nErrorCode: SecurityRuleParameterContainsUnsupportedValue\n\nContent:\n{\"error\":{\"code\":\"SecurityRuleParameterContainsUnsupportedValue\",\"message\":\"Security rule parameter DestinationAddressPrefix for rule with Id /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Network/networkSecurityGroups/acrchaos-aks-nsg/securityRules/ChaosDenyACRFakeRule cannot specify existing VIRTUALNETWORK, INTERNET, AZURELOADBALANCER, '*' or system tags. Unsupported value used: AzureContainerRegistry.\",\"details\":[]}}\n\nHeaders:\nCache-Control: no-cache\nPragma: no-cache\nx-ms-request-id: <guid>\nx-ms-client-request-id: <guid>\nx-ms-throttle-levels: REDACTED\nx-ms-correlation-request-id: REDACTED\nx-ms-arm-service-request-id: REDACTED\nStrict-Transport-Security: REDACTED\nx-ms-operation-identifier: REDACTED\nx-ms-ratelimit-remaining-subscription-writes: REDACTED\nx-ms-ratelimit-remaining-subscription-global-writes: REDACTED\nx-ms-routing-request-id: REDACTED\nX-Content-Type-Options: REDACTED\nX-Cache: REDACTED\nX-MSEdge-Ref: REDACTED\nDate: Tue, 07 Jul 2026 03:37:14 GMT\nContent-Length: 476\nContent-Type: application/json; charset=utf-8\nExpires: -1\n"
]
exit_code=0
```

### A1 final cancel Chaos experiment
```bash
az rest --method post --url 'https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a1-nsg-block-acr/cancel?api-version=2024-01-01' -o json; printf 'exit_code=%s\n' "$?"
```
```
exit_code=0
```

### A1 baseline ACR /v2/ from net-probe
```bash
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -w '%{http_code} %{time_total}s\n' -m 10 https://myregistry.azurecr.io/v2/
```
```
401 0.120472s
exit_code=0
```

### A1 baseline Bing control from net-probe
```bash
kubectl -n chaos-pullers exec net-probe -- curl -L -o /dev/null -s -w '%{http_code} %{time_total}s\n' -m 10 https://www.bing.com/
```
```
200 0.105978s
exit_code=0
```

### A1 resolved ACR IP
```
ACR_IP=<acr-public-ip>
```

### A1 create manual NSG deny for ACR CIDR
```bash
az network nsg rule create -g 'rg-acr-chaos' --nsg-name 'acrchaos-aks-nsg' -n ChaosBlockAcrCidr --priority 200 --direction Outbound --access Deny --protocol Tcp --destination-address-prefixes '<acr-public-ip>/32' --destination-port-ranges 443 --source-address-prefixes '*' --source-port-ranges '*' -o json
```
```
{
  "access": "Deny",
  "destinationAddressPrefix": "<acr-public-ip>/32",
  "destinationAddressPrefixes": [],
  "destinationPortRange": "443",
  "destinationPortRanges": [],
  "direction": "Outbound",
  "etag": "W/\"<guid>\"",
  "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Network/networkSecurityGroups/acrchaos-aks-nsg/securityRules/ChaosBlockAcrCidr",
  "name": "ChaosBlockAcrCidr",
  "priority": 200,
  "protocol": "Tcp",
  "provisioningState": "Succeeded",
  "resourceGroup": "rg-acr-chaos",
  "sourceAddressPrefix": "*",
  "sourceAddressPrefixes": [],
  "sourcePortRange": "*",
  "sourcePortRanges": [],
  "type": "Microsoft.Network/networkSecurityGroups/securityRules"
}
exit_code=0
```

### A1 during manual deny ACR /v2/
```bash
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -S -w '%{http_code} %{time_total}s\n' -m 10 https://myregistry.azurecr.io/v2/
```
```
curl: (28) Connection timed out after 10000 milliseconds
000 10.000771s
command terminated with exit code 28
exit_code=28
```

### A1 during manual deny Bing control
```bash
kubectl -n chaos-pullers exec net-probe -- curl -L -o /dev/null -s -S -w '%{http_code} %{time_total}s\n' -m 10 https://www.bing.com/
```
```
200 0.178784s
exit_code=0
```

### A1 cached workload state during deny
```bash
kubectl -n chaos-pullers get pods -o wide
```
```
NAME                          READY   STATUS    RESTARTS   AGE    IP            NODE                             NOMINATED NODE   READINESS GATES
cached-app-559d465548-b4n7q   1/1     Running   0          63m    10.224.0.68   aks-system-<vmss-id>-vmss   <none>           <none>
cached-app-559d465548-nhnx8   1/1     Running   0          63m    10.224.0.28   aks-system-<vmss-id>-vmss   <none>           <none>
cached-app-559d465548-q6kbs   1/1     Running   0          63m    10.224.0.37   aks-system-<vmss-id>-vmss   <none>           <none>
dns-probe                     1/1     Running   0          63m    10.224.0.54   aks-system-<vmss-id>-vmss   <none>           <none>
net-probe                     1/1     Running   0          8m7s   10.224.0.13   aks-system-<vmss-id>-vmss   <none>           <none>
exit_code=0
```

### A1 delete manual NSG deny
```bash
az network nsg rule delete -g 'rg-acr-chaos' --nsg-name 'acrchaos-aks-nsg' -n ChaosBlockAcrCidr
```
```

exit_code=0
```

### A1 recovery ACR /v2/
```bash
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -w '%{http_code} %{time_total}s\n' -m 10 https://myregistry.azurecr.io/v2/
```
```
401 0.073027s
exit_code=0
```

## Evidence
The command-output blocks above contain the Chaos execution failure, baseline, manual injection, during-injection, cached workload, cleanup, and recovery outputs.

## Result
PARTIAL — Azure Chaos Studio `securityRule/1.0` does not accept Azure service tags/system tags as destinations. The verified failure used `AzureContainerRegistry`; the same constraint applies to `MicrosoftContainerRegistry` and `AzureFrontDoor.FirstParty`. The experiment therefore used an explicit CIDR deny, which made ACR unreachable while the Bing control remained reachable; cached pods stayed Running; deleting the rule restored ACR reachability.

## Findings / limitations
Azure Chaos Studio's NSG security-rule fault does not accept Azure service tags/system tags as a destination in this path. Use explicit CIDR `destinationAddresses`; `infra/chaos.bicep` exposes this as `acrDenyCidrs` and defaults it to inert RFC 5737 TEST-NET space so it must be replaced with resolved registry CIDRs before A1 is run.

A `MicrosoftContainerRegistry` service tag does exist, but it does not make A1/F2 service-tag based: (a) the Chaos NSG fault rejects it because it is a system tag, and (b) even at an external firewall it does not cover the client-facing `mcr.microsoft.com` edge IPs, which are `AzureFrontDoor.FirstParty`. DNS faults such as A2 are the reliable way to disrupt MAR/MCR in this sample.

## Cleanup
Cancelled the Chaos experiment and deleted `ChaosBlockAcrCidr`; final cleanup verification is shown below.

### Mandatory cleanup verification
```
Name           ResourceGroup    Priority    SourcePortRanges    SourceAddressPrefixes    SourceASG    Access    Protocol    Direction    DestinationPortRanges                                                          DestinationAddressPrefixes    DestinationASG
-------------  ---------------  ----------  ------------------  -----------------------  -----------  --------  ----------  -----------  -----------------------------------------------------------------------------  ----------------------------  ----------------
NRMS-Rule-108  rg-acr-chaos     108         *                   Internet                 None         Deny      *           Inbound      13 17 19 53 69 111 123 512 514 593 873 1900 5353 11211                         *                             None
NRMS-Rule-103  rg-acr-chaos     103         *                   CorpNetPublic            None         Allow     *           Inbound      *                                                                              *                             None
NRMS-Rule-109  rg-acr-chaos     109         *                   Internet                 None         Deny      *           Inbound      119 137 138 139 161 162 389 636 2049 2301 2381 3268 5800 5900                  *                             None
NRMS-Rule-104  rg-acr-chaos     104         *                   CorpNetSaw               None         Allow     *           Inbound      *                                                                              *                             None
NRMS-Rule-101  rg-acr-chaos     101         *                   VirtualNetwork           None         Allow     Tcp         Inbound      443                                                                            *                             None
NRMS-Rule-105  rg-acr-chaos     105         *                   Internet                 None         Deny      *           Inbound      1433 1434 3306 4333 5432 6379 7000 7001 7199 9042 9160 9300 16379 26379 27017  *                             None
NRMS-Rule-106  rg-acr-chaos     106         *                   Internet                 None         Deny      Tcp         Inbound      22 3389                                                                        *                             None
NRMS-Rule-107  rg-acr-chaos     107         *                   Internet                 None         Deny      Tcp         Inbound      23 135 445 5985 5986                                                           *                             None
```
