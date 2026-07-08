# A3 — acrchaos-a3-registry-latency-loss (300 ms network delay to MCR)

- **Status:** PASS
- **Date (UTC):** 2026-07-07
- **Environment:** AKS `1.35` + Premium geo-replicated ACR (`eastus2`, registry `<registry>.azurecr.io`)
- **Injection mechanism:** Client-side Chaos Mesh **NetworkChaos** (`action: delay`, 300 ms + 50 ms jitter) to `mcr.microsoft.com`, selecting pods labeled `role=chaos-target`
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** This report demonstrates that Chaos Mesh network delay measurably increases MCR request latency without affecting untargeted traffic, and that cancellation restores baseline latency.

## Hypothesis
Adding network latency toward the registry slows requests measurably but they still succeed; a
non-targeted host is unaffected; latency returns to baseline after cancel.

## Steady-state signal
`curl -w %{time_total}` to `https://mcr.microsoft.com/v2/` from a curl-capable pod (`net-probe`,
`nicolaka/netshoot`). Baseline is tens of milliseconds; under a 300 ms per-packet delay the TLS
handshake's multiple round-trips add roughly a second.

## Steps
```bash
cd <repo>; source ./.chaos.env
SUB=$(az account show --query id -o tsv)
BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-acr-chaos/providers/Microsoft.Chaos/experiments/acrchaos-a3-registry-latency-loss"
# curl probe (busybox can't measure latency well)
kubectl -n chaos-pullers run net-probe --image=nicolaka/netshoot --labels role=chaos-target --restart=Never -- sleep 3600
# baseline
kubectl -n chaos-pullers exec net-probe -- sh -c 'for i in 1 2 3 4 5; do curl -o /dev/null -s -w "%{time_total}s\n" -m 15 https://mcr.microsoft.com/v2/; done'
az rest --method post --url "$BASE/start?api-version=2024-01-01"   # poll to Running; networkchaos AllInjected=True
# during
kubectl -n chaos-pullers exec net-probe -- sh -c 'for i in 1 2 3 4 5; do curl -o /dev/null -s -w "%{time_total}s\n" -m 20 https://mcr.microsoft.com/v2/; done'
kubectl -n chaos-pullers exec net-probe -- curl -o /dev/null -s -w "%{time_total}s\n" https://www.bing.com/   # control
az rest --method post --url "$BASE/cancel?api-version=2024-01-01"  # poll AllRecovered=True
```

## Evidence (curl `time_total` to `mcr.microsoft.com`)
```
BASELINE (no fault):        0.067s  0.065s  0.061s  0.049s  0.052s
DURING 300ms delay fault:   1.200s  1.306s  1.238s  1.368s  1.294s     <-- ~+1.2s (approx 4 RTTs x 300ms)
CONTROL www.bing.com (during, NOT targeted):  0.120s                    <-- unaffected (surgical)
AFTER cancel (recovered):   0.097s  0.148s  0.074s
```
NetworkChaos `AllInjected=True` reached within ~1s of Running; `AllRecovered=True` after cancel.

## Result
**PASS** — registry latency rose from ~0.05 s to ~1.3 s under the fault (requests still succeeded),
a non-targeted host stayed at ~0.12 s, and latency returned to baseline after cancel.

## Findings / limitations
- Measure latency with a **curl-capable** pod (`%{time_total}`); busybox `time`/`wget` did not provide reliable sub-second measurements. The repo includes a `net-probe` (netshoot) pod for this purpose.
- `delay` provides a clearer oracle than `loss` for a TLS endpoint, because packet loss appears only as occasional timeouts. This experiment uses `delay:300ms` rather than `loss:30%`.
- Experiment selects `role=chaos-target` pods so passive placeholder pods don't block `mode:all`.

## Cleanup
Cancelled `acrchaos-a3-registry-latency-loss`; NetworkChaos reached `AllRecovered=True`; latency returned to baseline.
