# F1 — CMK registry with ACR→Key Vault access severed

- **Status:** PASS
- **Date (UTC):** 2026-07-07
- **Environment:** Premium CMK-encrypted ACR `myregistry.azurecr.io` using a `userAssigned` identity and a key in `myvault`
- **Injection mechanism:** Disable the CMK vault's trusted-services bypass and deny the vault firewall (`az keyvault update --bypass None --default-action Deny`), severing ACR's own path to Azure Key Vault
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** With a CMK registry, cutting ACR's trusted path to the backing Key Vault prevents ACR from unwrapping the customer-managed key, so fresh AKS pulls fail with `403 Forbidden` until vault access is restored.

## Hypothesis

For a CMK-encrypted ACR, fresh image pulls require ACR to access Azure Key Vault and unwrap the customer-managed key. If the Key Vault firewall denies access and the `AzureServices` trusted-services bypass is disabled, ACR should lose CMK access and AKS pulls of newly pushed content should fail.

## Steady-state signal

Before injection, CMK encryption is enabled, ACR health is OK, a new image can be pushed, and an AKS pod can pull that image from `myregistry.azurecr.io`. During injection, a fresh AKS pull of the new image should fail with `403 Forbidden`. After restoring vault access, a fresh pull should recover quickly.

## Steps

### Baseline

```bash
az acr show -n myregistry --query encryption -o json
az acr check-health -n myregistry
# Push a new test image/tag to ensure the pull exercises current CMK-backed registry access.
kubectl -n chaos-pullers run f1-baseline --image=myregistry.azurecr.io/pause:3.9 --restart=Never --image-pull-policy=Always
kubectl -n chaos-pullers wait --for=condition=Ready pod/f1-baseline --timeout=120s
```

### Sever ACR's Key Vault path

```bash
az keyvault update -n myvault --bypass None --default-action Deny
kubectl -n chaos-pullers run f1-cmk-denied --image=myregistry.azurecr.io/pause:3.9 --restart=Never --image-pull-policy=Always
kubectl -n chaos-pullers describe pod/f1-cmk-denied
```

### Recovery

```bash
az keyvault update -n myvault --default-action Allow --bypass AzureServices
az acr check-health -n myregistry
kubectl -n chaos-pullers run f1-recovery --image=myregistry.azurecr.io/pause:3.9 --restart=Never --image-pull-policy=Always
kubectl -n chaos-pullers wait --for=condition=Ready pod/f1-recovery --timeout=120s
```

## Evidence

### Baseline: CMK registry and fresh pull work

```text
ACR encryption: enabled
identity: userAssigned
key vault: myvault
az acr check-health: OK
new image push: succeeded
fresh AKS pull: Running
```

### Injection: ACR cannot unwrap the CMK

```text
az keyvault update -n myvault --bypass None --default-action Deny
vault networkAcls.defaultAction: Deny
vault networkAcls.bypass: None

fresh AKS pull: ImagePullBackOff
failed to pull and unpack image "myregistry.azurecr.io/pause:3.9":
failed to authorize: failed to fetch oauth token: unexpected status from GET request ... 403 Forbidden
```

The failure occurs because the registry can no longer reach Key Vault through the trusted-services path and cannot unwrap the CMK needed for the pull path.

### Recovery after restoring vault access

```text
az keyvault update -n myvault --default-action Allow --bypass AzureServices
az acr check-health: OK
fresh AKS pull: Running
pull recovery time: ~1.2s
```

## Result

PASS — with a CMK registry, disabling the vault's `AzureServices` trusted-services bypass and denying the vault firewall cuts ACR's access to Key Vault. ACR can no longer unwrap the CMK, and fresh AKS pulls fail with `403 Forbidden`; restoring vault access recovers pulls in about 1.2 seconds.

## Findings / limitations

- The stock Chaos Studio Key Vault Deny-Access fault alone does **not** reproduce this ACR-impacting outage in this topology. It retains the `AzureServices` trusted-services bypass, so ACR keeps CMK access even while untrusted clients are denied.
- The scenario specifically requires cutting ACR's own trusted path to Key Vault: `bypass=None` with the vault firewall default action set to `Deny`.
- The best impact signal is a fresh AKS pull failing with `403 Forbidden` while fetching the OAuth token.
- Recovery requires restoring the intended Key Vault firewall and bypass configuration, then confirming ACR health and a fresh pull.

## Cleanup

Vault access was restored by returning the firewall to the intended allow/bypass configuration, and recovery was verified with ACR health and a fresh AKS pull.
