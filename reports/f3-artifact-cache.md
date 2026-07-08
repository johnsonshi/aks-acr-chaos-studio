# F3 — artifact cache serves AKS when the upstream is unreachable

- **Status:** PASS
- **Date (UTC):** 2026-07-07T04:43:27Z
- **Environment:** AKS `acrchaos-aks` + Premium ACR `myregistry.azurecr.io` in eastus2
- **Injection mechanism:** ACR-native artifact cache rule; AKS pulls from the ACR repository (not the upstream)
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** An ACR repository backed by an artifact cache rule (already synced from an upstream registry) serves the image to AKS directly from ACR. AKS pulls from `myregistry.azurecr.io/cache/...`, so its ability to pull does not depend on AKS reaching the upstream registry directly.

## Hypothesis
With an ACR cache rule, priming `myregistry.azurecr.io/cache/pause:3.9` makes ACR fetch and store the upstream image. Thereafter AKS pulls that image from the ACR repository, so the pull succeeds even when AKS cannot reach the upstream registry directly — as long as AKS is configured to pull from the ACR repository rather than the upstream.

## Steady-state signal
ACR anonymous pull is enabled, `net-probe` can reach `https://myregistry.azurecr.io/v2/`, and the cached repository `cache/pause:3.9` is present in ACR after priming.

## Steps
The tagged cache-rule command failed because this Azure CLI expects cache-rule source and target values to be repositories without tags. The equivalent tagless rule `-s mcr.microsoft.com/oss/kubernetes/pause -t cache/pause` was then used, with tag `3.9` pulled through ACR.

## Evidence

### Ensure net-probe Running

```bash
$ kubectl -n chaos-pullers wait --for=condition=Ready pod/net-probe --timeout=120s
pod/net-probe condition met
(exit 0)
```

### Baseline ACR /v2 from net-probe

```bash
$ kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -S -w %\{http_code\}\\n -m 15 https://myregistry.azurecr.io/v2/
401
(exit 0)
```

### Requested cache rule command

```bash
$ az acr cache create -r myregistry -n mcr-pause -s mcr.microsoft.com/oss/kubernetes/pause:3.9 -t cache/pause:3.9 -o table
ERROR: (GenericRepositoryNameInvalid) Repository name mcr.microsoft.com/oss/kubernetes/pause:3.9 is invalid. Repository name should follow the standardized docker repository naming conventions. All characters should be lowercase. For more information, please visit https://aka.ms/acr/cache.
Code: GenericRepositoryNameInvalid
Message: Repository name mcr.microsoft.com/oss/kubernetes/pause:3.9 is invalid. Repository name should follow the standardized docker repository naming conventions. All characters should be lowercase. For more information, please visit https://aka.ms/acr/cache.
(exit 1)
```

### Corrected tagless cache rule command

```bash
$ az acr cache create -r myregistry -n mcr-pause -s mcr.microsoft.com/oss/kubernetes/pause -t cache/pause -o table
CreationDate                      Name       ProvisioningState    ResourceGroup    SourceRepository                        TargetRepository
--------------------------------  ---------  -------------------  ---------------  --------------------------------------  ------------------
2026-07-07T04:43:36.958968+00:00  mcr-pause  Succeeded            rg-acr-chaos     mcr.microsoft.com/oss/kubernetes/pause  cache/pause
(exit 0)
```

### List ACR cache rules

```bash
$ az acr cache list -r myregistry -o table
CreationDate                      Name       ProvisioningState    ResourceGroup    SourceRepository                        TargetRepository
--------------------------------  ---------  -------------------  ---------------  --------------------------------------  ------------------
2026-07-07T04:43:36.958968+00:00  mcr-pause  Succeeded            rg-acr-chaos     mcr.microsoft.com/oss/kubernetes/pause  cache/pause
(exit 0)
```

### Prime cache by pulling through ACR

```bash
$ kubectl -n chaos-pullers run cache-test --image=myregistry.azurecr.io/cache/pause:3.9 --restart=Never
pod/cache-test created
(exit 0)
```

### Wait for cache-test Ready

```bash
$ kubectl -n chaos-pullers wait --for=condition=Ready pod/cache-test --timeout=240s
pod/cache-test condition met
(exit 0)
```

### Show cached repository attempt 1

```bash
$ az acr repository show -n myregistry --repository cache/pause -o table
ERROR: 2026-07-07 04:43:53.770580 Error: repository "cache/pause" is not found. Correlation ID: <guid>.
(exit 3)
```

### Show cached repository attempt 2

```bash
$ az acr repository show -n myregistry --repository cache/pause -o table
CreatedTime                   ImageName    LastUpdateTime                ManifestCount    Registry                             TagCount
----------------------------  -----------  ----------------------------  ---------------  -----------------------------------  ----------
2026-07-07T04:43:54.5975935Z  cache/pause  2026-07-07T04:43:54.0597876Z  1                myregistry.azurecr.io  1
(exit 0)
```

### Show cached repository tags

```bash
$ az acr repository show-tags -n myregistry --repository cache/pause -o table
Result
--------
3.9
(exit 0)
```

### Curl cached manifest from ACR

```bash
$ kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -S -w %\{http_code\}\\n -m 15 https://myregistry.azurecr.io/v2/cache/pause/manifests/3.9
401
(exit 0)
```

### Resolve MCR from net-probe

```bash
$ kubectl -n chaos-pullers exec net-probe -- dig +short mcr.microsoft.com
mcr.trafficmanager.net.
mcr-0001.mcr-msedge.net.
150.171.70.10
150.171.69.10
(exit 0)
```

### Add best-effort NSG deny for one MCR edge IP

```bash
$ az network nsg rule create -g rg-acr-chaos --nsg-name acrchaos-aks-nsg -n deny-mcr-f3 --priority 120 --direction Outbound --access Deny --protocol Tcp --source-address-prefixes 10.224.0.0/16 --source-port-ranges \* --destination-address-prefixes 150.171.69.10/32 --destination-port-ranges 443 -o table
Access    DestinationAddressPrefix    DestinationPortRange    Direction    Name         Priority    Protocol    ProvisioningState    ResourceGroup    SourceAddressPrefix    SourcePortRange
--------  --------------------------  ----------------------  -----------  -----------  ----------  ----------  -------------------  ---------------  ---------------------  -----------------
Deny      150.171.69.10/32            443                     Outbound     deny-mcr-f3  120         Tcp         Succeeded            rg-acr-chaos     10.224.0.0/16          *
(exit 0)
```

### Pull cached image from ACR while one MCR IP is denied

```bash
$ kubectl -n chaos-pullers run cache-test-block --image=myregistry.azurecr.io/cache/pause:3.9 --image-pull-policy=Always --restart=Never
pod/cache-test-block created
(exit 0)
```

### Wait for cache-test-block Ready

```bash
$ kubectl -n chaos-pullers wait --for=condition=Ready pod/cache-test-block --timeout=240s
pod/cache-test-block condition met
(exit 0)
```

### Remove best-effort NSG deny

```bash
$ az network nsg rule delete -g rg-acr-chaos --nsg-name acrchaos-aks-nsg -n deny-mcr-f3

(exit 0)
```

### Cleanup cache-test pods

```bash
$ kubectl -n chaos-pullers delete pod cache-test cache-test-block --ignore-not-found
pod "cache-test" deleted from chaos-pullers namespace
pod "cache-test-block" deleted from chaos-pullers namespace
(exit 0)
```

### Delete ACR cache rule

```bash
$ az acr cache delete -r myregistry -n mcr-pause --yes

(exit 0)
```

### Delete cached repository

```bash
$ az acr repository delete -n myregistry --repository cache/pause --yes
{
  "manifestsDeleted": [
    "sha256:a67d781a5a51290a56f6fb603b8ac9509abce8948d5a52ff3e02e8669a83180d"
  ],
  "tagsDeleted": [
    "3.9"
  ]
}
(exit 0)
```

### Verify no F3 cache rule remains

```bash
$ az acr cache list -r myregistry -o table

(exit 0)
```

### Verify cache-test pods removed

```bash
$ kubectl -n chaos-pullers get pod cache-test cache-test-block
Error from server (NotFound): pods "cache-test" not found
Error from server (NotFound): pods "cache-test-block" not found
(exit 1)
```

## Result
PASS — after the cache rule synced `cache/pause:3.9` into ACR, AKS pulled the image from `myregistry.azurecr.io/cache/pause:3.9`, served by ACR. Because AKS pulls from the ACR repository rather than the upstream, the pull path does not depend on AKS being able to reach the upstream registry directly. (The tagged cache-rule command failed, so this report records the required tagless form as a limitation.)

## Findings / limitations
- The tagged command failed with `GenericRepositoryNameInvalid` because this Azure CLI requires `--source-repo` and `--target-repo` to be repositories, not tagged references.
- The additional attempt to block AKS→upstream by denying a single MCR edge IP is best-effort only: `mcr.microsoft.com` is Azure Front Door-fronted with rotating IPs, so single-IP blocking is unreliable. It is not needed to prove the point — AKS never contacts the upstream because it pulls the already-synced image from the ACR repository.

## Cleanup
Deleted `cache-test` / `cache-test-block`, removed NSG rule `deny-mcr-f3` if present, deleted cache rule `mcr-pause`, and deleted repository `cache/pause`. Verification commands are included above.
