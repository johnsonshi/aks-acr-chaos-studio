# F2 — MAR/MCR edge block

- **Status:** PARTIAL
- **Date (UTC):** 2026-07-07T03:37:03Z
- **Environment:** AKS `v1.35.5` + ACR `myregistry` (login `myregistry.azurecr.io`, region eastus2)
- **Injection mechanism:** Manual NSG CIDR deny to one resolved MCR edge IP
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that single-IP NSG blocking is unreliable for MCR/MAR because the service is fronted by Azure Front Door and Traffic Manager.

## Hypothesis
Blocking outbound HTTPS to the MCR/MAR edge should make MCR unreachable from AKS; however MCR is AFD/Traffic-Manager fronted, so a single-IP CIDR block may be bypassed by alternate edge IPs.

## Steady-state signal
MCR `/v2/` returns quickly when reachable (HTTP 200 in this run); during injection, a true edge block should time out/fail; recovery restores quick HTTP success.

## Steps

### F2 baseline MCR /v2/ from net-probe
```bash
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -w '%{http_code} %{time_total}s\n' -m 10 https://mcr.microsoft.com/v2/
```
```
200 0.095391s
exit_code=0
```

### F2 dig mcr.microsoft.com
```bash
kubectl -n chaos-pullers exec net-probe -- dig +short mcr.microsoft.com
```
```
mcr.trafficmanager.net.
mcr-0001.mcr-msedge.net.
150.171.69.10
150.171.70.10
exit_code=0
```

### F2 selected MCR IP
```
MCR_IP=150.171.69.10
```

### F2 create manual NSG deny for one MCR CIDR
```bash
az network nsg rule create -g 'rg-acr-chaos' --nsg-name 'acrchaos-aks-nsg' -n ChaosBlockMcrCidr --priority 201 --direction Outbound --access Deny --protocol Tcp --destination-address-prefixes '150.171.69.10/32' --destination-port-ranges 443 --source-address-prefixes '*' --source-port-ranges '*' -o json
```
```
{
  "access": "Deny",
  "destinationAddressPrefix": "150.171.69.10/32",
  "destinationAddressPrefixes": [],
  "destinationPortRange": "443",
  "destinationPortRanges": [],
  "direction": "Outbound",
  "etag": "W/\"<guid>\"",
  "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Network/networkSecurityGroups/acrchaos-aks-nsg/securityRules/ChaosBlockMcrCidr",
  "name": "ChaosBlockMcrCidr",
  "priority": 201,
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

### F2 during manual deny MCR /v2/
```bash
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -S -w '%{http_code} %{time_total}s\n' -m 10 https://mcr.microsoft.com/v2/
```
```
200 0.065332s
exit_code=0
```

### F2 delete manual NSG deny
```bash
az network nsg rule delete -g 'rg-acr-chaos' --nsg-name 'acrchaos-aks-nsg' -n ChaosBlockMcrCidr
```
```

exit_code=0
```

### F2 recovery MCR /v2/
```bash
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -w '%{http_code} %{time_total}s\n' -m 10 https://mcr.microsoft.com/v2/
```
```
200 0.109676s
exit_code=0
```

## Evidence
The command-output blocks above show baseline DNS/curl, the selected IP, injection, during-injection behavior, cleanup, and recovery.

## Result
PARTIAL — the manual NSG deny to one resolved MCR edge IP did not stop access in this run (`curl` still returned HTTP 200), demonstrating that single-IP blocking is unreliable for Azure Front Door / Traffic Manager-fronted MCR/MAR. It does not represent a durable MAR outage.

## Findings / limitations
`mcr.microsoft.com` is fronted by Azure Front Door and Traffic Manager with rotating IPs, so single-IP blocking is unreliable. The Chaos Studio NSG fault also rejects the `MicrosoftContainerRegistry` and `AzureFrontDoor.FirstParty` service tags (system tags, as verified in A1), so service-tag blocking is not an option in the NSG fault either. For repeatable MAR/MCR disruption, prefer a Chaos Mesh DNS fault (as in A2), which targets the FQDN rather than a moving IP.

## Cleanup
Deleted `ChaosBlockMcrCidr`; final cleanup verification is shown below.

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
