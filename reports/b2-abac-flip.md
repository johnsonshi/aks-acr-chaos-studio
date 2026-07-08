# B2 — ABAC mode flip invalidates AcrPull-only pull access

- **Status:** PASS
- **Date (UTC):** 2026-07-07T03:50:58Z
- **Environment:** AKS `1.35` + Premium geo-replicated ACR (`eastus2` home, `westus3` replica)
- **Injection mechanism:** ACR-native authentication mode flip
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that switching ACR to RBAC+ABAC invalidates AcrPull-only data-plane access until the kubelet identity receives repository-scoped reader permission.

## Hypothesis

Flipping the registry from RBAC-only to RBAC+ABAC should invalidate AcrPull-only data-plane access.
A fresh pull should fail until the kubelet identity receives `Container Registry Repository Reader`.

## Steady-state signal

Before ABAC, the kubelet identity has `AcrPull` on the registry.
With anonymous pull disabled and ABAC enabled, a fresh `imagePullPolicy: Always` pull should fail.
After granting `Container Registry Repository Reader`, a recreated pod should pull and run.

## Steps

```bash
cd aks-acr-chaos-studio
source ./.chaos.env
OBJID=$(az aks show -g rg-acr-chaos -n "$AKS_NAME" --query identityProfile.kubeletidentity.objectId -o tsv)
ACR_ID=$(az acr show -n "$ACR_NAME" --query id -o tsv)
RID=$(az role definition list --name "Container Registry Repository Reader" --query "[0].name" -o tsv)
az acr show -n "$ACR_NAME" --query roleAssignmentMode -o tsv
az role assignment list --assignee "$OBJID" --all -o table
az acr update -n "$ACR_NAME" --anonymous-pull-enabled false -o none
az acr update -n "$ACR_NAME" --role-assignment-mode rbac-abac -o table
kubectl -n chaos-pullers apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: abac-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: abac-test
  template:
    metadata:
      labels:
        app: abac-test
    spec:
      containers:
      - name: pause
        image: $ACR_LOGIN/samples/pause:3.9
        imagePullPolicy: Always
YAML
kubectl -n chaos-pullers rollout status deployment/abac-test --timeout=60s
kubectl -n chaos-pullers describe pod -l app=abac-test
az role assignment create \
  --assignee-object-id "$OBJID" \
  --assignee-principal-type ServicePrincipal \
  --role "$RID" \
  --scope "$ACR_ID"
kubectl -n chaos-pullers delete pod -l app=abac-test --ignore-not-found=true
kubectl -n chaos-pullers rollout status deployment/abac-test --timeout=300s
az acr update -n "$ACR_NAME" --role-assignment-mode rbac -o none
az acr update -n "$ACR_NAME" --anonymous-pull-enabled true -o none
kubectl -n chaos-pullers delete deployment abac-test --ignore-not-found=true
```

## Evidence

```text
### Inputs
ACR=myregistry
ACR_LOGIN=myregistry.azurecr.io
AKS=acrchaos-aks
OBJID=<guid>
RID=<guid>
### Step 1: current roleAssignmentMode
LegacyRegistryPermissions
### Confirm kubelet roles for negative test
Role     Scope
-------  ---------------------------------------------------------------------------------------------------------------------------------------------------------
AcrPull  /subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-acr-chaos/providers/Microsoft.ContainerRegistry/registries/myregistry
### Step 3: disable anonymous pull
disable anon rc=0
### Step 4: flip to ABAC
WARNING: Warning: You have successfully updated the registry authentication mode to enable RBAC Registry + ABAC Repository Permissions. ACR Tasks within the registry that do not have an assigned identity for source registry access will not have data plane access to the registry. To configure source registry data plane access for your existing Tasks, you must explicitly assign an Entra identity for accessing the source registry using the '--source-registry-auth-id' flag in 'az acr task update'. Please refer to https://aka.ms/acr/auth/abac for more details.
Name                      RoleAssignmentMode         AnonymousPullEnabled
------------------------  -------------------------  ----------------------
myregistry  AbacRepositoryPermissions  False
flip rc=0
### Confirm ABAC mode
{
  "anon": false,
  "mode": "AbacRepositoryPermissions"
}
### Step 5: create abac-test deployment (negative pull)
deployment.apps/abac-test created
Waiting for deployment "abac-test" rollout to finish: 0 of 1 updated replicas are available...
error: timed out waiting for the condition
negative rollout rc=1
### Negative pod status
NAME                         READY   STATUS         RESTARTS   AGE   IP            NODE                             NOMINATED NODE   READINESS GATES
abac-test-6ff6555f5d-pmlx2   0/1     ErrImagePull   0          61s   10.224.0.60   aks-system-<vmss-id>-vmss   <none>           <none>
POD=abac-test-6ff6555f5d-pmlx2
### Negative pod waiting state
ErrImagePull
[failed to pull and unpack image "myregistry.azurecr.io/samples/pause:3.9": failed to resolve image: pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed, failed to pull and unpack image "myregistry.azurecr.io/samples/pause:3.9": failed to resolve image: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://myregistry.azurecr.io/oauth2/token?scope=repository%3Asamples%2Fpause%3Apull&service=myregistry.azurecr.io: 401 Unauthorized]
### Negative pod events
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  61s                default-scheduler  Successfully assigned chaos-pullers/abac-test-6ff6555f5d-pmlx2 to aks-system-<vmss-id>-vmss
  Warning  Failed     61s                kubelet            Failed to pull image "myregistry.azurecr.io/samples/pause:3.9": [failed to pull and unpack image "myregistry.azurecr.io/samples/pause:3.9": failed to resolve image: failed to authorize: failed to fetch oauth token: unexpected status from GET request to https://myregistry.azurecr.io/oauth2/token?scope=repository%3Asamples%2Fpause%3Apull&service=myregistry.azurecr.io: 401 Unauthorized, failed to pull and unpack image "myregistry.azurecr.io/samples/pause:3.9": failed to resolve image: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://myregistry.azurecr.io/oauth2/token?scope=repository%3Asamples%2Fpause%3Apull&service=myregistry.azurecr.io: 401 Unauthorized]
  Normal   Pulling    21s (x3 over 61s)  kubelet            Pulling image "myregistry.azurecr.io/samples/pause:3.9"
  Warning  Failed     21s (x3 over 61s)  kubelet            Error: ErrImagePull
  Warning  Failed     21s (x2 over 47s)  kubelet            Failed to pull image "myregistry.azurecr.io/samples/pause:3.9": [failed to pull and unpack image "myregistry.azurecr.io/samples/pause:3.9": failed to resolve image: pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed, failed to pull and unpack image "myregistry.azurecr.io/samples/pause:3.9": failed to resolve image: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://myregistry.azurecr.io/oauth2/token?scope=repository%3Asamples%2Fpause%3Apull&service=myregistry.azurecr.io: 401 Unauthorized]
  Normal   BackOff    10s (x3 over 61s)  kubelet            Back-off pulling image "myregistry.azurecr.io/samples/pause:3.9"
  Warning  Failed     10s (x3 over 61s)  kubelet            Error: ImagePullBackOff
### Step 6: grant Repository Reader
Scope                                                                                                                                                      PrincipalId
---------------------------------------------------------------------------------------------------------------------------------------------------------  ------------------------------------
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.ContainerRegistry/registries/myregistry  <guid>
repo reader create rc=0
### Roles after Repository Reader grant
Role                                  Scope
------------------------------------  ---------------------------------------------------------------------------------------------------------------------------------------------------------
AcrPull                               /subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-acr-chaos/providers/Microsoft.ContainerRegistry/registries/myregistry
Container Registry Repository Reader  /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acr-chaos/providers/Microsoft.ContainerRegistry/registries/myregistry
### Recreate pod and wait for success
pod "abac-test-6ff6555f5d-pmlx2" deleted from chaos-pullers namespace
Waiting for deployment "abac-test" rollout to finish: 0 of 1 updated replicas are available...
deployment "abac-test" successfully rolled out
positive rollout rc=0
### Positive pod status
NAME                         READY   STATUS    RESTARTS   AGE   IP            NODE                             NOMINATED NODE   READINESS GATES
abac-test-6ff6555f5d-9k52g   1/1     Running   0          16s   10.224.0.72   aks-system-<vmss-id>-vmss   <none>           <none>
POD2=abac-test-6ff6555f5d-9k52g
### Positive pod container state
Running
true
2026-07-07T03:50:28Z
### RESTORE: delete abac-test deployment
deployment.apps "abac-test" deleted from chaos-pullers namespace
### RESTORE: roleAssignmentMode=rbac and anonymousPullEnabled=true
mode restore rc=0
anon restore rc=0
{
  "anon": true,
  "mode": "LegacyRegistryPermissions"
}
```

## Result

PASS — ABAC mode caused an AcrPull-only kubelet pull to fail with `401 Unauthorized` / `ImagePullBackOff`. Granting `Container Registry Repository Reader` allowed the recreated pod to pull and run.

## Findings / limitations

The negative test requires the kubelet identity to have only `AcrPull`; `Container Registry Repository Reader` was removed before the negative pull and granted again before the positive pull. The role remained in place after the test as allowed by the instructions.

## Cleanup

The registry was restored to non-ABAC mode, anonymous pull was restored to `true`, and the `abac-test` deployment was deleted.
