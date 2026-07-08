# Client-side regional-endpoint failover (C1b)

ACR regional endpoints are direct, per-region registry FQDNs in the form `myregistry.<region>.geo.azurecr.io`. They are not containerd registry mirrors, and they do not require `hosts.toml`.

## Enable regional endpoints

Regional endpoints must be enabled once on a Premium registry:

```bash
az acr update --name myregistry --regional-endpoints enabled
az acr show-endpoints --name myregistry --output json
```

`az acr show-endpoints` should include a `regionalEndpoints` array, for example:

```text
myregistry.eastus2.geo.azurecr.io
myregistry.westus3.geo.azurecr.io
```

## Reference a regional endpoint directly

Use the regional FQDN as the image registry host:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: regional-pull
spec:
  replicas: 1
  selector:
    matchLabels:
      app: regional-pull
  template:
    metadata:
      labels:
        app: regional-pull
    spec:
      imagePullSecrets:
        - name: acr-regional-pull
      containers:
        - name: app
          image: myregistry.eastus2.geo.azurecr.io/app:tag
          imagePullPolicy: Always
```

For CLI or Docker workflows, target a regional endpoint explicitly, for example:

```bash
az acr login --name myregistry --endpoint eastus2
```

## Client-side failover model

A pinned regional endpoint does not automatically reroute to another region. Client-side failover means changing the client target to a different regional FQDN, such as moving from `myregistry.eastus2.geo.azurecr.io/app:tag` to `myregistry.westus3.geo.azurecr.io/app:tag`.

## AKS credential-provider caveat

Default AKS managed ACR authentication matches `*.azurecr.io` and the sovereign-cloud suffixes with the same domain-part count. That matches `myregistry.azurecr.io`, but it does not match five-part regional names such as `myregistry.eastus2.geo.azurecr.io`. Without another credential path, kubelet supplies no credentials, containerd falls back to anonymous, and the pull fails with `401 Unauthorized` / `ImagePullBackOff`.

Use one of these workarounds:

1. Supply explicit pull credentials, such as an `imagePullSecret` built from an ACR token. This was verified in C1b.
2. Keep the global hostname `myregistry.azurecr.io`, which the managed credential provider matches, and use DNS-based routing to resolve it to the chosen regional endpoint. This approach was not verified in the C1b run.
3. Customize the node credential-provider configuration to add a regional pattern such as `*.*.geo.azurecr.io`. This requires node customization and is not default AKS.

## What C1b observes

C1b validates whether a regional-endpoint failover design can pull from each regional FQDN and whether the AKS credential path is correctly wired. The important hidden failure mode is that a regional FQDN failover can look like a network-routing change but fail as an authentication problem unless credentials are included.
