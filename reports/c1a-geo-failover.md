# C1a — Global-endpoint geo-failover by replica routing exclusion

- **Status:** PASS
- **Date (UTC):** 2026-07-07T03:50:58Z
- **Environment:** AKS `1.35` + Premium geo-replicated ACR (`eastus2` home, `westus3` replica)
- **Injection mechanism:** ACR-native global endpoint routing toggle
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that excluding one replica from global endpoint routing leaves the global ACR endpoint reachable through the remaining replica.

## Hypothesis

Excluding the `westus3` replica from global endpoint routing should not break the global ACR endpoint.
The global endpoint should continue serving `/v2/` through the remaining `eastus2` replica.

## Steady-state signal

`az acr replication list` shows both replicas `Ready`.
A net-probe pod in `chaos-pullers` receives HTTP `401` from `https://$ACR_LOGIN/v2/`,
which means the registry data plane is reachable and auth is required.

## Steps

```bash
cd aks-acr-chaos-studio
source ./.chaos.env
az acr replication list -r "$ACR_NAME" -o table
kubectl -n chaos-pullers exec net-probe -- sh -c \
  "curl -o /dev/null -s -w '%{http_code}\n' -m 10 https://$ACR_LOGIN/v2/"
az acr replication update -r "$ACR_NAME" -n westus3 --global-endpoint-routing false -o table
az acr replication list -r "$ACR_NAME" -o table
kubectl -n chaos-pullers exec net-probe -- sh -c \
  "curl -o /dev/null -s -w '%{http_code}\n' -m 10 https://$ACR_LOGIN/v2/"
az acr replication update -r "$ACR_NAME" -n westus3 --global-endpoint-routing true -o table
az acr replication list -r "$ACR_NAME" -o table
```

## Evidence

```text
### AKS version
1.35
### Replication baseline
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True
eastus2  eastus2     Succeeded             Ready     True
### Net probe pod
NAME                          READY   STATUS    RESTARTS   AGE   IP            NODE                             NOMINATED NODE   READINESS GATES
cached-app-559d465548-b4n7q   1/1     Running   0          69m   10.224.0.68   aks-system-<vmss-id>-vmss   <none>           <none>
cached-app-559d465548-nhnx8   1/1     Running   0          69m   10.224.0.28   aks-system-<vmss-id>-vmss   <none>           <none>
cached-app-559d465548-q6kbs   1/1     Running   0          69m   10.224.0.37   aks-system-<vmss-id>-vmss   <none>           <none>
dns-probe                     1/1     Running   0          69m   10.224.0.54   aks-system-<vmss-id>-vmss   <none>           <none>
net-probe                     1/1     Running   0          13m   10.224.0.13   aks-system-<vmss-id>-vmss   <none>           <none>
PROBE=net-probe
### Baseline curl global /v2/
401
### Disable westus3 global endpoint routing
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     False
### Observe replications after disable
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     False
eastus2  eastus2     Succeeded             Ready     True
### Curl after disable
401
### Restore westus3 global endpoint routing
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True
### Verify replications restored
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True
eastus2  eastus2     Succeeded             Ready     True
```

## Result

PASS — the `westus3` global endpoint routing toggle worked, and the global endpoint continued to serve HTTP `401`.

## Findings / limitations

This experiment did not directly observe DNS or Traffic Manager reroute from a client near `westus3`. The client ran in the `eastus2` AKS cluster, and DNS TTL/reroute behavior can take minutes. The observed result demonstrates the self-service exclusion toggle and continued global endpoint reachability.

## Cleanup

`westus3` global endpoint routing was restored to `True`. Final replication verification showed both `eastus2` and `westus3` `Ready` with endpoint enabled.
