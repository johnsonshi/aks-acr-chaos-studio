# C1b — regional-endpoint failover

- **Status:** PARTIAL
- **Date (UTC):** 2026-07-07
- **Environment:** AKS `v1.35.5` + Premium geo-replicated ACR (home `eastus2`, replica `westus3`)
- **Injection mechanism:** Regional endpoint direct-FQDN pull plus client-side failover to another regional FQDN
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** ACR regional endpoints are directly addressable after registry enablement, but default AKS managed ACR credentials do not match regional FQDNs; explicit pull credentials are required unless another workaround is used.

## Hypothesis

When ACR regional endpoints are enabled, a client can pull from a specific replica by referencing `myregistry.<region>.geo.azurecr.io` directly and can fail over by switching to a different regional FQDN.

## Steady-state signal

`az acr show-endpoints` returns `regionalEndpoints`; the global endpoint pull succeeds with AKS managed credentials; regional endpoint pulls succeed when explicit pull credentials are supplied.

## Steps

### Enable and inspect regional endpoints

```bash
az acr update -n myregistry --regional-endpoints enabled
az acr show-endpoints -n myregistry -o json
```

### Pull matrix

Run five pods with `imagePullPolicy: Always` against the imported image `myregistry/pause:3.9`:

```bash
# global endpoint, no imagePullSecret
image: myregistry.azurecr.io/pause:3.9

# regional endpoints, no imagePullSecret
image: myregistry.eastus2.geo.azurecr.io/pause:3.9
image: myregistry.westus3.geo.azurecr.io/pause:3.9

# regional endpoints, explicit imagePullSecret from an ACR token
image: myregistry.eastus2.geo.azurecr.io/pause:3.9
image: myregistry.westus3.geo.azurecr.io/pause:3.9
```

### Inspect AKS credential-provider matching

```bash
# on an AKS node
sudo cat /var/lib/kubelet/credential-provider-config.yaml
```

## Evidence

### Regional endpoints are enabled

```text
az acr update -n myregistry --regional-endpoints enabled
az acr show-endpoints -n myregistry ->
  loginServer: myregistry.azurecr.io
  dataEndpoints: myregistry.eastus2.data.azurecr.io, myregistry.westus3.data.azurecr.io
  regionalEndpoints: myregistry.eastus2.geo.azurecr.io, myregistry.westus3.geo.azurecr.io
```

### Pull test matrix

```text
pause-global        myregistry.azurecr.io/pause:3.9                no secret (managed provider)  -> Running
pause-eastus2       myregistry.eastus2.geo.azurecr.io/pause:3.9    no secret                     -> ImagePullBackOff (401)
pause-westus3       myregistry.westus3.geo.azurecr.io/pause:3.9    no secret                     -> ImagePullBackOff (401)
pause-eastus2-auth  myregistry.eastus2.geo.azurecr.io/pause:3.9    imagePullSecret (ACR token)   -> Running (pulled 607ms)
pause-westus3-auth  myregistry.westus3.geo.azurecr.io/pause:3.9    imagePullSecret (ACR token)   -> Running (pulled 1.993s)
```

A second independent live pull re-confirmed the same credential behavior: the global endpoint pod reached `Running`, while both regional endpoint pods stayed in `ImagePullBackOff` with `failed to fetch anonymous token ... 401 Unauthorized`.

### Exact regional no-credential error

```text
Failed to pull image "myregistry.eastus2.geo.azurecr.io/pause:3.9": ... failed to authorize:
failed to fetch anonymous token: unexpected status from GET request to
https://myregistry.eastus2.geo.azurecr.io/oauth2/token?scope=repository%3Apause%3Apull&service=myregistry.azurecr.io: 401 Unauthorized
```

Containerd fell back to anonymous because kubelet supplied no credentials for the regional FQDN.

### Root cause: managed credential-provider match rules

```text
providers: acr-credential-provider
matchImages: ["*.azurecr.io","*.azurecr.cn","*.azurecr.de","*.azurecr.us"]
args: /etc/kubernetes/azure.json
```

There are two independent code-level gates that reject the five-part regional FQDN form:

1. Kubernetes `matchImages` requires the image host to have the same number of dot-separated parts as the configured pattern. `*.azurecr.io` has three parts and matches the global endpoint `myregistry.azurecr.io`, but `myregistry.eastus2.geo.azurecr.io` has five parts, so the managed `acr-credential-provider` is not invoked for regional FQDNs.
2. Even if the provider were invoked, the ACR credential provider's own image test recognizes only a single alphanumeric registry label before `.azurecr.io`. `myregistry.azurecr.io` matches that shape; `myregistry.<region>.geo.azurecr.io` does not.

## Result

PARTIAL — regional endpoints work and both replicas independently served pulls when explicit credentials were provided, but default AKS managed ACR authentication does not apply to regional FQDN image references, so a direct regional-endpoint failover design must also wire credentials or use another workaround.

## Findings / limitations

- ACR regional endpoints are real, directly addressable FQDNs in the form `myregistry.<region>.geo.azurecr.io` after `--regional-endpoints enabled`; containerd registry mirrors and `hosts.toml` are not involved.
- Client-side failover means changing the image reference or client target from one regional FQDN to another. There is no automatic reroute for a pinned regional endpoint.
- The no-secret result was re-confirmed by a second independent live pull: the global endpoint pod reached `Running`, and both regional endpoint pods stayed in `ImagePullBackOff` with `failed to fetch anonymous token ... 401 Unauthorized`.
- On default AKS, direct regional FQDNs fail with `401 Unauthorized` unless credentials are supplied because two separate matching gates require the single-label host shape: kubelet's credential-provider `matchImages` rule requires the same domain-part count as `*.azurecr.io`, and the ACR credential provider's own image test only recognizes one alphanumeric registry label before `.azurecr.io`.
- Workaround proven in this run: supply explicit pull credentials, such as an `imagePullSecret` built from an ACR token.
- Workaround not verified in this run: keep the global hostname `myregistry.azurecr.io` so the credential provider matches, then use DNS-based routing to resolve it to a chosen regional endpoint.
- Workaround requiring node customization: add a regional pattern such as `*.*.geo.azurecr.io` to the node credential-provider configuration; this is not default AKS.
- Chaos-testing relevance: a failover design that swaps to `<region>.geo.azurecr.io` FQDNs can silently become an authentication failure on AKS unless credentials are included.

## Cleanup

No C1b fault was injected in this evidence run. Test pods and explicit pull credentials should be removed after validation.
