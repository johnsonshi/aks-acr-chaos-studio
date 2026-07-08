# D1 — Pull storm / throttling

- **Status:** PARTIAL
- **Date (UTC):** 2026-07-07T03:53:56Z
- **Environment:** AKS `1.35.5` + Premium geo-replicated ACR (`eastus2` home, `westus3` replica)
- **Injection mechanism:** Load
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that the configured pull storm generated substantial ACR traffic but did not reach Premium throttling limits in the observed window.

## Hypothesis

A 50-way pull storm against `samples/pause:3.9` may exceed ACR request limits and produce HTTP `429` / `TOOMANYREQUESTS` with client backoff.

## Steady-state signal

The Kubernetes Job runs pullers against the real ACR. Throttling evidence is either client log lines matching `429|TOOMANYREQUESTS|Retry-After` or Log Analytics rows with `ResultDescription == "429"`.

## Steps

```bash
cd aks-acr-chaos-studio
source ./.chaos.env
kubectl -n chaos-pullers delete job pull-storm --ignore-not-found
kubectl -n chaos-pullers apply -f workloads/rendered/pull-storm-job.yaml
kubectl -n chaos-pullers wait --for=condition=complete job/pull-storm --timeout=600s
kubectl -n chaos-pullers get job pull-storm -o wide
kubectl -n chaos-pullers logs -l app=pull-storm --tail=-1 --prefix=true | grep -iE "429|TOOMANYREQUESTS|Retry-After" | head -n 40
az monitor log-analytics query -w "$(az monitor log-analytics workspace show --ids "$LAW_ID" --query customerId -o tsv)" \
  --analytics-query 'ContainerRegistryRepositoryEvents | where TimeGenerated > ago(15m) | summarize total=count(), throttled=countif(tostring(ResultDescription)=="429") by bin(TimeGenerated,1m)' -o table
```

## Evidence

```text
### Environment baseline
ACR_NAME=myregistry
ACR_LOGIN=myregistry.azurecr.io
AKS_NAME=acrchaos-aks
SUB=00000000-0000-0000-0000-000000000000
Client Version: v1.34.1
Server Version: v1.35.5
NAME     LOCATION    PROVISIONING STATE    STATUS    REGION ENDPOINT ENABLED
-------  ----------  --------------------  --------  -------------------------
westus3  westus3     Succeeded             Ready     True
eastus2  eastus2     Succeeded             Ready     True

### D1 clean/apply/wait
job.batch/pull-storm created
error: timed out waiting for the condition on jobs/pull-storm
WAIT_RESULT=not_complete_or_timeout

### D1 job status at 600s
NAME         STATUS    COMPLETIONS   DURATION   AGE   CONTAINERS   IMAGES                                    SELECTOR
pull-storm   Running   44/50         10m        10m   puller       gcr.io/go-containerregistry/crane:debug   batch.kubernetes.io/controller-uid=<guid>

### D1 logs sample
[pod/pull-storm-8d8zz/puller] done 200 iterations
[pod/pull-storm-knc2x/puller] done 200 iterations
[pod/pull-storm-lcwpt/puller] done 200 iterations
[pod/pull-storm-pzjsv/puller] done 200 iterations
[pod/pull-storm-289cp/puller] done 200 iterations
[pod/pull-storm-8zq9r/puller] done 200 iterations
[pod/pull-storm-b7j2r/puller] done 200 iterations
[pod/pull-storm-fvpj6/puller] done 200 iterations
[pod/pull-storm-jwq6j/puller] done 200 iterations
[pod/pull-storm-x4czp/puller] done 200 iterations
[pod/pull-storm-4rp9d/puller] done 200 iterations
[pod/pull-storm-6d4ff/puller] done 200 iterations
[pod/pull-storm-7hzz4/puller] done 200 iterations
[pod/pull-storm-cmhkf/puller] done 200 iterations
[pod/pull-storm-dw6b6/puller] done 200 iterations
[pod/pull-storm-nvw24/puller] done 200 iterations
[pod/pull-storm-txmn6/puller] done 200 iterations
[pod/pull-storm-wcpr8/puller] done 200 iterations
[pod/pull-storm-hg7fx/puller] done 200 iterations
[pod/pull-storm-htt7x/puller] done 200 iterations
[pod/pull-storm-r845c/puller] done 200 iterations
[pod/pull-storm-wvrdb/puller] done 200 iterations
[pod/pull-storm-2pv6k/puller] done 200 iterations
[pod/pull-storm-6r5sk/puller] done 200 iterations
[pod/pull-storm-754lb/puller] done 200 iterations
[pod/pull-storm-8wg56/puller] done 200 iterations
[pod/pull-storm-mlhl8/puller] done 200 iterations
[pod/pull-storm-rjgg5/puller] done 200 iterations
[pod/pull-storm-lhbsn/puller] done 200 iterations
[pod/pull-storm-ltw8w/puller] done 200 iterations
[pod/pull-storm-qqr4r/puller] done 200 iterations
[pod/pull-storm-vm955/puller] done 200 iterations
[pod/pull-storm-9nqd5/puller] done 200 iterations
[pod/pull-storm-bh5rx/puller] done 200 iterations
[pod/pull-storm-bmk7v/puller] done 200 iterations
[pod/pull-storm-d74fn/puller] done 200 iterations
[pod/pull-storm-52fft/puller] done 200 iterations
[pod/pull-storm-6pz8g/puller] done 200 iterations
[pod/pull-storm-7nh8m/puller] done 200 iterations
[pod/pull-storm-8z44n/puller] done 200 iterations
[pod/pull-storm-f5276/puller] done 200 iterations
[pod/pull-storm-f5ms2/puller] done 200 iterations
[pod/pull-storm-g782q/puller] done 200 iterations
[pod/pull-storm-xvfql/puller] done 200 iterations

### D1 throttle grep
THROTTLE_GREP_STATUS=1
THROTTLE_LINE_COUNT=0

### D1 Log Analytics last 15m
TableName      TimeGenerated         Throttled    Total
-------------  --------------------  -----------  -------
PrimaryResult  2026-07-07T03:56:00Z  0            5700
PrimaryResult  2026-07-07T03:57:00Z  0            5973
PrimaryResult  2026-07-07T03:58:00Z  0            5606
PrimaryResult  2026-07-07T03:59:00Z  0            1960
PrimaryResult  2026-07-07T03:53:00Z  0            2
PrimaryResult  2026-07-07T03:54:00Z  0            3967
PrimaryResult  2026-07-07T03:55:00Z  0            5841
PrimaryResult  2026-07-07T04:00:00Z  0            299
PrimaryResult  2026-07-07T04:01:00Z  0            121
PrimaryResult  2026-07-07T04:02:00Z  0            43
PrimaryResult  2026-07-07T04:03:00Z  0            19
```

## Result

PARTIAL — the pull storm ran against ACR with configured volume `50 x 200 = 10,000` iterations (`crane manifest` + `crane pull` each loop). At the 600s wait limit, 44/50 pods had completed, so at least 8,800 iterations finished. No client or Log Analytics `429` was observed; Log Analytics showed 29,531 repository events in the window and `throttled=0` for every minute.

## Findings / limitations

ACR Premium throttling limits are high; reaching HTTP 429 requires far higher concurrency than this run generated. The rendered workload redirects `crane` command output to `/dev/null`, so client-side per-call errors would only be visible indirectly via job completion behavior or Log Analytics unless the workload is changed to preserve stderr/stdout.

## Cleanup

The `pull-storm` job was deleted during final cleanup. `westus3` routing remained enabled.
