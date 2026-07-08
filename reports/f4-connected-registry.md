# F4 — Connected registry offline

- **Status:** ⬜ BLOCKED
- **Date (UTC):** 2026-07-07T04:55:08Z
- **Environment:** Current stack is AKS-in-Azure + Premium ACR only; no Azure Arc / IoT Edge connected-registry host
- **Injection mechanism:** Dependency — disconnect edge connected registry from parent ACR

## Hypothesis
A connected registry should keep serving already-synchronized cached content to local edge clients while disconnected from its parent ACR.

## Steady-state signal (oracle)
Before injection, an Azure Arc-enabled Kubernetes or IoT Edge host runs an active connected registry, required repositories are synchronized from the parent Premium ACR, and local clients can pull through the connected registry endpoint.

## What was done (reproducible steps)
```bash
# No Azure mutation was performed. This is a design/infra gate check:
# the current repo stack deploys AKS in Azure and does not provision an Arc-enabled
# edge host or IoT Edge runtime for connected registry.
```

To repro F4 with the required infra:
```bash
# 1. Use a Premium parent ACR.
az acr show -n "$ACR_NAME" --query "sku.name" -o tsv

# 2. Create a connected registry and sync token/scope for the repositories under test.
az acr connected-registry create \
  --registry "$ACR_NAME" \
  --name <connected-registry-name> \
  --repository <repo>:<tag> \
  --mode ReadOnly

# 3. Deploy the connected registry to an Azure Arc-enabled Kubernetes cluster
#    or IoT Edge host, using the generated sync token/settings.

# 4. Prime/synchronize content, then verify local edge clients can pull from the
#    connected registry endpoint while connected to the parent.

# 5. Cut only the edge host's link to the parent ACR (NSG/firewall/agent block),
#    leaving local client-to-edge connectivity intact.

# 6. Verify cached/synchronized tags still pull locally while new uncached content
#    or sync operations fail until the parent link is restored.
```

## Evidence
```
No connected-registry edge host is present in this AKS-in-Azure stack.
```

## Result
BLOCKED — connected registry is an on-premises/edge replica pattern, and this stack does not include the required Arc-enabled Kubernetes or IoT Edge host.

## Findings / gotchas
- Required infra: Premium ACR, `az acr connected-registry create`, sync token/client token configuration, and an Azure Arc-enabled Kubernetes or IoT Edge host.
- Connected registry is an on-premises/remote replica that synchronizes artifacts with a cloud ACR, is Premium-only, and can run on Azure Arc-enabled Kubernetes, using a sync token to communicate with its parent.
- The resilience test is not an Azure-region ACR outage test; it is an edge-disconnect test. Cut the edge host's parent link and prove cached local content is still served.

## Cleanup
None — no connected registry was created and no Azure resources were mutated.
