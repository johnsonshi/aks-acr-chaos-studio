# A5 — Private endpoint / private DNS failure

- **Status:** PASS
- **Date (UTC):** 2026-07-07
- **Environment:** AKS `v1.35.5` + Premium ACR `myregistry.azurecr.io` (home `eastus2`), VNet with an `aks` subnet
- **Injection mechanism:** Disable ACR public network access, then restore reachability with an ACR private endpoint (`group-id registry`) and `privatelink.azurecr.io` private DNS linked to the AKS VNet
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** When ACR public network access is disabled, AKS pulls have no public fallback. A private endpoint plus private DNS becomes the required and sufficient connectivity path for fresh AKS pulls.

## Hypothesis

With public network access enabled, AKS can pull from `myregistry.azurecr.io` through the normal public ACR endpoint. After `az acr update --public-network-enabled false`, a fresh pull should fail unless the AKS VNet has private endpoint connectivity and private DNS resolution for ACR. Once the private endpoint and DNS zone are in place, the same pull should succeed while public access remains disabled.

## Steady-state signal

A fresh pod using `imagePullPolicy: Always` pulls `myregistry.azurecr.io/pause:3.9` successfully before the outage. During the outage window, a newly created pod fails with `403 Forbidden` while fetching the ACR OAuth token. After private endpoint and private DNS configuration, ACR names resolve to private IPs and a newly created pod reaches `Running` while `publicNetworkAccess` remains disabled.

## Steps

### Phase 1 — baseline public path

```bash
kubectl -n chaos-pullers run a5-baseline --image=myregistry.azurecr.io/pause:3.9 --restart=Never --image-pull-policy=Always
kubectl -n chaos-pullers wait --for=condition=Ready pod/a5-baseline --timeout=120s
```

### Phase 2 — disable public access with no private endpoint

```bash
az acr update -n myregistry --public-network-enabled false
kubectl -n chaos-pullers run a5-no-private-path --image=myregistry.azurecr.io/pause:3.9 --restart=Never --image-pull-policy=Always
kubectl -n chaos-pullers describe pod/a5-no-private-path
```

### Phase 3 — add private endpoint and private DNS

```bash
az network private-endpoint create \
  --name acr-pe \
  --group-id registry \
  --connection-name acr-pe-conn \
  --vnet-name <vnet> \
  --subnet <private-endpoint-subnet> \
  --private-connection-resource-id <acr-resource-id>

az network private-dns zone create -n privatelink.azurecr.io
az network private-dns link vnet create -z privatelink.azurecr.io -n aks-link -v <aks-vnet-id> -e false
az network private-endpoint dns-zone-group create \
  --endpoint-name acr-pe \
  -n registry \
  --zone-name registry \
  --private-dns-zone privatelink.azurecr.io

kubectl -n chaos-pullers run a5-private-path --image=myregistry.azurecr.io/pause:3.9 --restart=Never --image-pull-policy=Always
kubectl -n chaos-pullers wait --for=condition=Ready pod/a5-private-path --timeout=120s
```

## Evidence

### Phase 1 — baseline pull works with public access enabled

```text
publicNetworkAccess: Enabled
image: myregistry.azurecr.io/pause:3.9
fresh AKS pull: Running
```

### Phase 2 — public access disabled, no private endpoint

```text
az acr update -n myregistry --public-network-enabled false
publicNetworkAccess: Disabled

fresh AKS pull: ImagePullBackOff
failed to pull and unpack image "myregistry.azurecr.io/pause:3.9":
failed to resolve reference "myregistry.azurecr.io/pause:3.9":
failed to authorize: failed to fetch oauth token: unexpected status from GET request ... 403 Forbidden
```

This is the key no-fallback signal: with public access off and no private endpoint path, a fresh AKS pull reaches ACR's public auth path but receives a hard `403 Forbidden` instead of falling back to another public route.

### Phase 3 — private endpoint and private DNS restore pulls

```text
private endpoint group-id: registry
private DNS zone: privatelink.azurecr.io
private DNS zone linked to the AKS VNet
publicNetworkAccess: Disabled
```

Name resolution from the AKS VNet moved onto private endpoint addresses:

```text
myregistry.azurecr.io                 -> myregistry.privatelink.azurecr.io -> 10.224.0.95
myregistry.eastus2.data.azurecr.io    -> private endpoint IP
myregistry.westus3.data.azurecr.io    -> private endpoint IP
myregistry.eastus2.geo.azurecr.io     -> private endpoint IP
myregistry.westus3.geo.azurecr.io     -> private endpoint IP
```

A new pod pull succeeded over the private path while public access stayed disabled:

```text
image: myregistry.azurecr.io/pause:3.9
fresh AKS pull: Running
pull duration: ~655ms
publicNetworkAccess: Disabled
```

## Result

PASS — disabling ACR public network access made a fresh AKS pull fail with `403 Forbidden` while fetching the OAuth token when no private endpoint path existed. After creating the ACR private endpoint and linking `privatelink.azurecr.io` private DNS to the AKS VNet, ACR login, data, and regional endpoint names resolved to private IPs and a fresh AKS pull succeeded in about 655 ms while public access remained disabled.

## Findings / limitations

- The private endpoint is the sole working connectivity path for this topology when public network access is disabled.
- Absence or loss of the private endpoint/private DNS path has no public fallback for fresh AKS pulls; the observed failure is a hard `403 Forbidden` during OAuth token fetch.
- Private DNS is part of the dependency. The login endpoint, dedicated data endpoints, and regional endpoint names must resolve privately from the AKS VNet.
- This run proves the end-to-end AKS pull behavior for a fresh pull. Already-cached images can still start without contacting ACR and should not be used as the outage oracle.

## Cleanup

Public network access and private endpoint resources should be restored or removed according to the intended post-test environment. The evidence run verified the failure and recovery behavior before the stack was torn down.
