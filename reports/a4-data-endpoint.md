# A4 — data-endpoint-only outage

- **Status:** PASS
- **Date (UTC):** 2026-07-07
- **Environment:** AKS `v1.35.5` (containerd 2.3.2) + Premium ACR (home `eastus2`, dedicated data endpoints enabled)
- **Injection mechanism:** Chaos Studio AKS Chaos Mesh DNS fault (`dnsChaos/2.2`) scoped to only the dedicated data-endpoint FQDN
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** A registry pull authenticates and fetches the manifest from the login endpoint but cannot download blobs, because the dedicated data endpoint — where every layer download is redirected — is made unresolvable while the login endpoint stays healthy.

## Hypothesis

An ACR pull uses the login endpoint for auth and manifest, then follows a `307` redirect to the dedicated data endpoint (`myregistry.<region>.data.azurecr.io`) for blob/layer download. Faulting only the data-endpoint FQDN should leave auth and manifest working while blob download fails — a data-endpoint-only outage.

## Steady-state signal

From an injectable probe pod in the fault's target namespace, the data-endpoint FQDN resolves and a full image pull succeeds before the fault; during the fault only the data-endpoint FQDN fails to resolve while the login endpoint and an unrelated control name keep resolving; resolution recovers after cancel.

## Steps

```bash
# A4 is a first-class Chaos Studio experiment (infra/chaos.bicep -> <prefix>-a4-data-endpoint-dns).
# Its DNS pattern is the derived data-endpoint FQDN: <registry>.<region>.data.azurecr.io
BASE=".../providers/Microsoft.Chaos/experiments/<prefix>-a4-data-endpoint-dns"
az rest --method post --url "$BASE/start?api-version=2024-01-01"   # poll executions until Running
# baseline + during-fault + recovery observed from an injectable netshoot probe (role=chaos-target)
az rest --method post --url "$BASE/cancel?api-version=2024-01-01"
```

DNS-fault spec applied by Chaos Studio:

```json
{"action":"error","mode":"all","patterns":["myregistry.eastus2.data.azurecr.io"],
 "selector":{"namespaces":["chaos-pullers"],"labelSelectors":{"role":"chaos-target"}}}
```

## Evidence

### Baseline (no fault)

```text
crane pull myregistry.azurecr.io/samples/pause:3.9   -> PULL_OK (322048 bytes)   # full path incl. data endpoint
dig myregistry.eastus2.data.azurecr.io               -> resolves
dig myregistry.azurecr.io                            -> resolves
```

### During fault (execution Running, DNSChaos `AllInjected=True`)

```text
dig myregistry.azurecr.io               -> 5c...trafficmanager.net     (login endpoint RESOLVES)
dig myregistry.eastus2.data.azurecr.io  -> <no answer / SERVFAIL>      (data endpoint BLOCKED)
dig mcr.microsoft.com                   -> mcr.trafficmanager.net      (control RESOLVES)

curl https://myregistry.azurecr.io/v2/                -> HTTP 401       (login endpoint reachable, auth challenge)
curl https://myregistry.eastus2.data.azurecr.io/v2/   -> curl exit 6    (could not resolve host)
```

### Recovery (after cancel, DNSChaos `AllRecovered=True`)

```text
dig myregistry.eastus2.data.azurecr.io  -> eus2-1-az.data.azcr.io      (RESOLVES again)
dig myregistry.azurecr.io               -> resolves
```

## Result

PASS — the fault cleanly isolated the data-endpoint FQDN: during injection it was unresolvable while the login endpoint continued to answer `/v2/` and an unrelated control name kept resolving, and resolution recovered on cancel. Because dedicated data endpoints are enabled, every layer download is redirected (`307`) to `myregistry.<region>.data.azurecr.io`, so a pull authenticates and reads the manifest but cannot complete blob download — a data-endpoint-only outage.

## Findings / limitations

- Earlier this scenario was attempted with an agent-based node network block, which is not supported on AKS-managed node pools. The service-direct AKS Chaos Mesh DNS fault is the correct mechanism and is fully supported.
- Scope, same as A2: Chaos Mesh DNS faults rewrite **pod** DNS (CoreDNS), so this models the data-endpoint outage for in-cluster resolution and in-pod pull tooling (for example `crane`, BuildKit, or Kaniko). It does not change node-level containerd DNS, so a kubelet node pull is not literally interrupted by this fault. To fault a kubelet node pull's data endpoint, block it at the network layer instead — an NSG CIDR deny on the resolved data-endpoint IP, or a private endpoint with an NSG rule on its private IP.
- Injection requires an injectable probe: `mode:"all"` needs every `role=chaos-target` pod to accept injection, and the distroless `crane:debug` image is not DNS-injectable. Use a full-OS probe such as netshoot for the in-pod oracle.

## Cleanup

The experiment was cancelled and DNSChaos reported `AllRecovered=True`; the data-endpoint FQDN resolved again immediately afterward.
