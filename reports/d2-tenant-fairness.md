# D2 — Tenant fairness

- **Status:** PARTIAL
- **Date (UTC):** 2026-07-07T04:04:00Z
- **Environment:** AKS `1.35.5` + Premium geo-replicated ACR (`eastus2` home, `westus3` replica)
- **Injection mechanism:** Load with two repository-scoped token identities
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that the victim tenant completed successfully during the noisy-tenant load, while noting that the load did not reach throttling saturation.

## Hypothesis

A noisy tenant using token `tenantA` should not starve a victim tenant using token `tenantB`; per-identity-per-registry limits should preserve tenant B success.

## Steady-state signal

Victim job `fairness-b-victim` prints `tenant-b results: ok=<n> fail=<n>`. Healthy means high `ok` and low/zero `fail` while `fairness-a-noisy` is running.

## Steps

```bash
cd aks-acr-chaos-studio
source ./.chaos.env
kubectl -n chaos-pullers delete job pull-storm fairness-a-noisy fairness-b-victim --ignore-not-found
kubectl -n chaos-pullers apply -f workloads/rendered/tenant-fairness-a.yaml -f workloads/rendered/tenant-fairness-b.yaml
kubectl -n chaos-pullers wait --for=condition=complete job/fairness-b-victim --timeout=240s
kubectl -n chaos-pullers logs -l app=fairness,identity=tenant-b --tail=-1 --prefix=true
kubectl -n chaos-pullers wait --for=condition=complete job/fairness-a-noisy --timeout=360s
kubectl -n chaos-pullers get job fairness-a-noisy fairness-b-victim -o wide
kubectl -n chaos-pullers logs -l app=fairness --tail=-1 --prefix=true | grep -iE "429|TOOMANYREQUESTS|Retry-After" | head -n 40
```

## Evidence

```text
### D2 clean/apply
job.batch "pull-storm" deleted from chaos-pullers namespace
job.batch/fairness-a-noisy created
job.batch/fairness-b-victim created

### D2 wait victim
error: timed out waiting for the condition on jobs/fairness-b-victim
VICTIM_WAIT=not_complete_or_timeout

### D2 victim job status during first check
NAME                STATUS    COMPLETIONS   DURATION   AGE    CONTAINERS   IMAGES                                    SELECTOR
fairness-b-victim   Running   1/2           4m1s       4m1s   puller       gcr.io/go-containerregistry/crane:debug   batch.kubernetes.io/controller-uid=<guid>

### D2 tenant-b logs during first check
[pod/fairness-b-victim-csq8q/puller] tenant-b results: ok=60 fail=0

### D2 wait noisy/status
error: timed out waiting for the condition on jobs/fairness-a-noisy
NOISY_WAIT=not_complete_or_timeout
NAME               STATUS    COMPLETIONS   DURATION   AGE   CONTAINERS   IMAGES                                    SELECTOR
fairness-a-noisy   Running   29/40         10m        10m   puller       gcr.io/go-containerregistry/crane:debug   batch.kubernetes.io/controller-uid=<guid>

### D2 final post-check
NAME                STATUS     COMPLETIONS   DURATION   AGE   CONTAINERS   IMAGES                                    SELECTOR
fairness-a-noisy    Running    29/40         10m        10m   puller       gcr.io/go-containerregistry/crane:debug   batch.kubernetes.io/controller-uid=<guid>
fairness-b-victim   Complete   2/2           4m56s      10m   puller       gcr.io/go-containerregistry/crane:debug   batch.kubernetes.io/controller-uid=<guid>

### D2 tenant-b final logs
[pod/fairness-b-victim-5qbn2/puller] tenant-b results: ok=60 fail=0
[pod/fairness-b-victim-csq8q/puller] tenant-b results: ok=60 fail=0

### D2 tenant-a final status counts
Running 11
Completed 29

### D2 throttle grep all fairness
FAIRNESS_THROTTLE_LINE_COUNT=0

### D2 Log Analytics last 15m
TableName      TimeGenerated         Throttled    Total
-------------  --------------------  -----------  -------
PrimaryResult  2026-07-07T04:05:00Z  0            2067
PrimaryResult  2026-07-07T04:06:00Z  0            2845
PrimaryResult  2026-07-07T04:07:00Z  0            2582
PrimaryResult  2026-07-07T04:08:00Z  0            921
PrimaryResult  2026-07-07T04:10:00Z  0            281
PrimaryResult  2026-07-07T04:11:00Z  0            40
PrimaryResult  2026-07-07T04:12:00Z  0            14
PrimaryResult  2026-07-07T04:13:00Z  0            11
PrimaryResult  2026-07-07T04:00:00Z  0            73
PrimaryResult  2026-07-07T04:01:00Z  0            121
PrimaryResult  2026-07-07T04:02:00Z  0            43
PrimaryResult  2026-07-07T04:03:00Z  0            45
PrimaryResult  2026-07-07T04:04:00Z  0            23
PrimaryResult  2026-07-07T04:09:00Z  0            271
PrimaryResult  2026-07-07T04:14:00Z  0            5
```

## Result

PARTIAL — Tenant B stayed healthy: two victim pods completed with aggregate `ok=120 fail=0`. Tenant A generated load with configured volume `40 x 300 = 12,000` manifest requests, but only 29/40 noisy pods completed by the bounded wait, and no 429s were observed. Because neither identity saturated ACR limits, this run shows no victim impact at this scale but does not prove per-identity isolation under throttling.

## Findings / limitations

ACR Premium throttling limits are high; reaching HTTP 429 requires far higher concurrency than this run generated. The victim job took just under 5 minutes for both completions and remained error-free.

## Cleanup

`fairness-a-noisy` and `fairness-b-victim` were deleted before D3/final cleanup.
