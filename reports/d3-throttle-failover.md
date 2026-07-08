# D3 — throttling while failing over between replicas

- **Status:** PARTIAL
- **Date (UTC):** 2026-07-07T04:15:00Z
- **Environment:** AKS `1.35.5` + Premium geo-replicated ACR (`eastus2` home, `westus3` replica)
- **Injection mechanism:** ACR-native global endpoint routing toggle + load
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report exercises throttling behavior while pull traffic fails over from one geo-replica to another: removing the `westus3` replica from global-endpoint routing concentrates pulls on `eastus2`, then load is driven against that single replica. It documents that the bounded storm did not reach Premium throttling limits at this scale.

## Hypothesis

Disabling `westus3` from global endpoint routing concentrates global endpoint pull traffic on `eastus2`. Because ACR throttling is per-geo-replica as well as per registry/identity, concentrating traffic on one replica should make 429s more likely than normal two-replica routing.

## Steady-state signal

`westus3` routing is disabled during the storm and restored afterward. Throttling evidence is client log lines matching `429|TOOMANYREQUESTS|Retry-After` or Log Analytics rows with `ResultDescription == "429"`.

## Steps

```bash
cd aks-acr-chaos-studio
source ./.chaos.env
kubectl -n chaos-pullers delete job pull-storm fairness-a-noisy fairness-b-victim --ignore-not-found
az acr replication list -r "$ACR_NAME" -o table
az acr replication update -r "$ACR_NAME" -n westus3 --global-endpoint-routing false -o table
az acr replication list -r "$ACR_NAME" -o table
kubectl -n chaos-pullers apply -f workloads/rendered/pull-storm-job.yaml
kubectl -n chaos-pullers wait --for=condition=complete job/pull-storm --timeout=600s
kubectl -n chaos-pullers get job pull-storm -o wide
kubectl -n chaos-pullers logs -l app=pull-storm --tail=-1 --prefix=true | grep -iE "429|TOOMANYREQUESTS|Retry-After" | head -n 40
az acr replication update -r "$ACR_NAME" -n westus3 --global-endpoint-routing true -o table
az acr replication list -r "$ACR_NAME" -o table
```

## Evidence

```text
### D3 pre-clean
job.batch "fairness-a-noisy" deleted from chaos-pullers namespace
job.batch "fairness-b-victim" deleted from chaos-pullers namespace

### D3 baseline replications
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True
eastus2  eastus2     Succeeded             Ready     True

### D3 disable westus3 routing
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     False

### D3 replications after disable
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     False
eastus2  eastus2     Succeeded             Ready     True

### D3 apply/wait pull storm
job.batch/pull-storm created
error: timed out waiting for the condition on jobs/pull-storm
D3_WAIT_RESULT=not_complete_or_timeout

### D3 job status at 600s
NAME         STATUS    COMPLETIONS   DURATION   AGE   CONTAINERS   IMAGES                                    SELECTOR
pull-storm   Running   6/50          10m        10m   puller       gcr.io/go-containerregistry/crane:debug   batch.kubernetes.io/controller-uid=<guid>

### D3 pod status summary from captured output
6 Completed, 19 Running, 25 Pending at the 600s wait boundary.

### D3 logs sample
[pod/pull-storm-r7rpj/puller] done 200 iterations
[pod/pull-storm-g44wd/puller] done 200 iterations
[pod/pull-storm-k2kfm/puller] done 200 iterations
[pod/pull-storm-p9wpd/puller] done 200 iterations
[pod/pull-storm-z9nhh/puller] done 200 iterations
[pod/pull-storm-k6drf/puller] done 200 iterations

### D3 throttle grep
D3_THROTTLE_LINE_COUNT=0

### D3 Log Analytics last 15m
TableName      TimeGenerated         Throttled    Total
-------------  --------------------  -----------  -------
PrimaryResult  2026-07-07T04:20:00Z  0            556
PrimaryResult  2026-07-07T04:21:00Z  0            394
PrimaryResult  2026-07-07T04:22:00Z  0            244
PrimaryResult  2026-07-07T04:23:00Z  0            123
PrimaryResult  2026-07-07T04:24:00Z  0            63
PrimaryResult  2026-07-07T04:25:00Z  0            21
PrimaryResult  2026-07-07T04:11:00Z  0            4
PrimaryResult  2026-07-07T04:12:00Z  0            14
PrimaryResult  2026-07-07T04:13:00Z  0            11
PrimaryResult  2026-07-07T04:14:00Z  0            5
PrimaryResult  2026-07-07T04:15:00Z  0            5
PrimaryResult  2026-07-07T04:16:00Z  0            1608
PrimaryResult  2026-07-07T04:17:00Z  0            1683
PrimaryResult  2026-07-07T04:18:00Z  0            1158
PrimaryResult  2026-07-07T04:19:00Z  0            796

### D3 restore westus3 routing
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True

### D3 replications after restore
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True
eastus2  eastus2     Succeeded             Ready     True
```

## Result

PARTIAL — the experiment removed `westus3` from global endpoint routing, ran the pull storm, and restored routing. The configured storm volume was `50 x 200 = 10,000` iterations (`crane manifest` + `crane pull` each loop), but at the 600s boundary only 6/50 pods had completed and 25 were still Pending. No client or Log Analytics 429s were observed; Log Analytics showed 6,685 repository events from 04:16-04:25 with `throttled=0`.

## Findings / limitations

Concentrating traffic onto one replica reduces available per-replica headroom, but ACR Premium throttling limits are high and this bounded run did not reach HTTP 429. Capacity guidance remains: keep 2-3 replicas in global routing for headroom and failover, especially before planned regional events or unusually high pull volume.

## Cleanup

`westus3` global endpoint routing was restored to `True`. `pull-storm` was deleted during final cleanup, and final replication verification showed both replicas Ready and in routing.
