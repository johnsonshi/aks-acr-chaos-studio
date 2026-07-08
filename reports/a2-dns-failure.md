# A2 — acrchaos-a2-dns-failure

- **Status:** PASS
- **Date (UTC):** 2026-07-07T03:03:25Z
- **Environment:** AKS `1.35` + Premium geo-replicated ACR (region `eastus2`, registry `myregistry.azurecr.io`)
- **Injection mechanism:** Chaos Mesh DNSChaos error for `mcr.microsoft.com` and `myregistry.azurecr.io`
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates targeted DNS failure for registry FQDNs while unrelated DNS resolution remains healthy and recovery occurs after cancellation.

## Hypothesis
Registry DNS failures should be injected only for registry FQDNs from the observation pod, while an unrelated control name still resolves; after cancel, registry DNS should recover.

## Steady-state signal
From pod `chaos-pullers/dns-probe`, registry and control names resolve before the experiment. During injection, only the registry FQDN lookups fail. After cancel, `mcr.microsoft.com` resolves again.

## Steps
```bash
cd aks-acr-chaos-studio
source ./.chaos.env
RG=rg-acr-chaos
REGION=eastus2
SUB=(az account show --query id -o tsv)
BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a2-dns-failure"
kubectl -n chaos-pullers exec dns-probe -- nslookup mcr.microsoft.com
kubectl -n chaos-pullers exec dns-probe -- nslookup $ACR_LOGIN
kubectl -n chaos-pullers exec dns-probe -- nslookup example.com
az rest --method post --url "$BASE/start?api-version=2024-01-01"
az rest --method get --url "$BASE/executions?api-version=2024-01-01" -o json
kubectl get dnschaos -n chaos-testing -o json
kubectl -n chaos-pullers exec dns-probe -- nslookup mcr.microsoft.com
kubectl -n chaos-pullers exec dns-probe -- nslookup $ACR_LOGIN
kubectl -n chaos-pullers exec dns-probe -- nslookup example.com
az rest --method post --url "$BASE/cancel?api-version=2024-01-01"
kubectl get dnschaos -n chaos-testing -o json
kubectl -n chaos-pullers exec dns-probe -- nslookup mcr.microsoft.com
```

## Evidence

### Baseline
```
$ kubectl -n chaos-pullers exec dns-probe -- nslookup mcr.microsoft.com
Server:		10.0.0.10
Address:	10.0.0.10:53

Non-authoritative answer:
mcr.microsoft.com	canonical name = mcr.trafficmanager.net
mcr.trafficmanager.net	canonical name = mcr-0001.mcr-msedge.net
Name:	mcr-0001.mcr-msedge.net
Address: 150.171.69.10
Name:	mcr-0001.mcr-msedge.net
Address: 150.171.70.10

Non-authoritative answer:
mcr.microsoft.com	canonical name = mcr.trafficmanager.net
mcr.trafficmanager.net	canonical name = mcr-0001.mcr-msedge.net
Name:	mcr-0001.mcr-msedge.net
Address: 2603:1061:f:100::10
Name:	mcr-0001.mcr-msedge.net
Address: 2603:1061:f:101::10
[exit=0]

$ kubectl -n chaos-pullers exec dns-probe -- nslookup myregistry.azurecr.io
Server:		10.0.0.10
Address:	10.0.0.10:53

Non-authoritative answer:
myregistry.azurecr.io	canonical name = <registry-guid>.trafficmanager.net
<registry-guid>.trafficmanager.net	canonical name = <...>.fe.azcr.io
<...>.fe.azcr.io	canonical name = <...>.trafficmanager.net
<...>.trafficmanager.net	canonical name = <regional-endpoint>.eastus2.cloudapp.azure.com

Non-authoritative answer:
myregistry.azurecr.io	canonical name = <registry-guid>.trafficmanager.net
<registry-guid>.trafficmanager.net	canonical name = <...>.fe.azcr.io
<...>.fe.azcr.io	canonical name = <...>.trafficmanager.net
<...>.trafficmanager.net	canonical name = <regional-endpoint>.eastus2.cloudapp.azure.com
Name:	<regional-endpoint>.eastus2.cloudapp.azure.com
Address: <acr-public-ip>
[exit=0]

$ kubectl -n chaos-pullers exec dns-probe -- nslookup example.com
Server:		10.0.0.10
Address:	10.0.0.10:53

Non-authoritative answer:
Name:	example.com
Address: 172.66.147.243
Name:	example.com
Address: 104.20.23.154

Non-authoritative answer:
Name:	example.com
Address: 2606:4700:10::ac42:93f3
Name:	example.com
Address: 2606:4700:10::6814:179a
[exit=0]
```

### Start and injection
```
$ az rest --method post --url "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a2-dns-failure/start?api-version=2024-01-01"

[exit=0]

$ az rest --method get --url "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a2-dns-failure/executions?api-version=2024-01-01" -o json  # poll until Running
03:03:30Z status=PreProcessing
03:03:41Z status=PreProcessing
03:03:51Z status=PreProcessing
03:04:02Z status=WaitingToStart
03:04:13Z status=Running
[wait_exit=0]

$ kubectl get dnschaos -n chaos-testing -o json | jq ... AllInjected poll
03:04:14Z dnschaos AllInjected=True
[wait_exit=0]
```

### During fault
```
$ kubectl -n chaos-pullers exec dns-probe -- nslookup mcr.microsoft.com
Server:		10.0.59.216
Address:	10.0.59.216:53

** server can't find mcr.microsoft.com: SERVFAIL

** server can't find mcr.microsoft.com: SERVFAIL

command terminated with exit code 1
[exit=1]

$ kubectl -n chaos-pullers exec dns-probe -- nslookup myregistry.azurecr.io
Server:		10.0.59.216
Address:	10.0.59.216:53

** server can't find myregistry.azurecr.io: SERVFAIL

** server can't find myregistry.azurecr.io: SERVFAIL

command terminated with exit code 1
[exit=1]

$ kubectl -n chaos-pullers exec dns-probe -- nslookup example.com
Server:		10.0.59.216
Address:	10.0.59.216:53

Non-authoritative answer:
Name:	example.com
Address: 2606:4700:10::ac42:93f3
Name:	example.com
Address: 2606:4700:10::6814:179a

Non-authoritative answer:
Name:	example.com
Address: 104.20.23.154
Name:	example.com
Address: 172.66.147.243
[exit=0]
```

### Cancel and recovery
```
$ az rest --method post --url "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a2-dns-failure/cancel?api-version=2024-01-01"

[exit=0]

$ kubectl get dnschaos -n chaos-testing -o json | jq ... AllRecovered poll
03:04:18Z dnschaos AllRecovered=False
03:04:23Z dnschaos AllRecovered=False
03:04:29Z dnschaos AllRecovered=False
03:04:34Z dnschaos AllRecovered=False
03:04:40Z dnschaos AllRecovered=False
03:04:45Z dnschaos AllRecovered=True
[wait_exit=0]

$ kubectl -n chaos-pullers exec dns-probe -- nslookup mcr.microsoft.com
Server:		10.0.0.10
Address:	10.0.0.10:53

Non-authoritative answer:
mcr.microsoft.com	canonical name = mcr.trafficmanager.net
mcr.trafficmanager.net	canonical name = mcr-0001.mcr-msedge.net
Name:	mcr-0001.mcr-msedge.net
Address: 150.171.69.10
Name:	mcr-0001.mcr-msedge.net
Address: 150.171.70.10

Non-authoritative answer:
mcr.microsoft.com	canonical name = mcr.trafficmanager.net
mcr.trafficmanager.net	canonical name = mcr-0001.mcr-msedge.net
Name:	mcr-0001.mcr-msedge.net
Address: 2603:1061:f:101::10
Name:	mcr-0001.mcr-msedge.net
Address: 2603:1061:f:100::10
[exit=0]
```

### Cleanup state
```
$ kubectl get dnschaos,networkchaos -A -o json | jq ... conditions
DNSChaos	chaos-testing	<guid>	False	True
DNSChaos	chaos-testing	<guid>	False	True
NetworkChaos	chaos-testing	<guid>	False	True
[exit=0]
```

## Result
PASS — mcr.microsoft.com lookup exit=1 during fault, myregistry.azurecr.io lookup exit=1 during fault, example.com control lookup exit=0, and post-cancel mcr.microsoft.com lookup exit=0.

## Findings / limitations
The experiment selected the `role=chaos-target` pod and reached `AllInjected=True`; the control domain remained resolvable during the registry DNS failure.

## Cleanup
Cancelled `acrchaos-a2-dns-failure` and observed DNSChaos `AllRecovered=True`. Final cleanup state above shows no active injection for the latest resources.
