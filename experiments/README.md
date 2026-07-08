# Experiments

This directory contains Azure Chaos Studio experiment definitions that are not fully represented by the Bicep deployment. Most day-to-day scenarios are deployed from `infra/chaos.bicep`; the JSON files here are portable definitions for scenarios that require additional target onboarding.

## Bicep-deployed experiments

`infra/chaos.bicep` deploys the primary Chaos Studio targets, capabilities, role assignments, and experiments.

| Experiment | Deployed name | Mechanism | Notes |
|---|---|---|---|
| A1 — full registry unreachable | `acrchaos-a1-nsg-block-acr` | NSG deny to registry CIDR ranges | Use `acrDenyCidrs`; the Chaos NSG fault rejects all Azure service tags/system tags as destinations. |
| A2 — registry DNS failure | `acrchaos-a2-dns-failure` | AKS Chaos Mesh DNS Chaos | Requires Chaos Mesh setup from `scripts/10-setup-chaos-mesh.sh`. |
| A3 — registry latency/loss | `acrchaos-a3-registry-latency-loss` | AKS Chaos Mesh Network Chaos | Requires Chaos Mesh. |
| F1 — CMK registry with ACR→Key Vault access severed | `acrchaos-f1-keyvault-denyaccess` plus vault firewall bypass update | Disable the CMK vault trusted-services bypass | Requires `ENABLE_CMK=true`; the stock Deny-Access fault alone keeps `AzureServices` bypass, so sever ACR→Key Vault with `--bypass None --default-action Deny`. |

Deploy the Bicep experiments through the standard lifecycle:

```bash
make cycle RG=rg-acr-chaos PREFIX=acrchaos LOCATION=<region> AKS_VM_SIZE=<sku>
make experiments
make run EXP=acrchaos-a2-dns-failure
```

## JSON experiments

The JSON files in this directory are `Microsoft.Chaos/experiments` request bodies with placeholders for target resource IDs. Use them when an experiment requires a target that cannot be reliably created in the base Bicep flow.

| Experiment | File | Required target |
|---|---|---|
| B1 — IMDS / node-identity loss | `b1-imds-agent.json` | Chaos Studio agent target on the node VMSS. AKS-managed node pools do not support the required VM extension path. |
| C2 — AKS availability-zone loss | `c2-vmss-az-shutdown.json` | VMSS Chaos target for a zone-pinned node pool. |

## Deploy a JSON experiment

Substitute placeholders, create the experiment with Azure Resource Manager, grant the experiment identity the required role on the target, then start the experiment.

```bash
export LOCATION=eastus
export RG=rg-acr-chaos
export NAME=acrchaos-b1-imds
export AGENT_TARGET_ID="<vmssId>/providers/Microsoft.Chaos/targets/Microsoft-Agent"

SUB=$(az account show --query id -o tsv)

az rest --method put \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Chaos/experiments/$NAME?api-version=2024-01-01" \
  --body "$(envsubst < b1-imds-agent.json)"

az chaos experiment start -g "$RG" -n "$NAME"
```

For production-quality game days, keep the identity scope narrow, use short durations, and run against a dedicated test cluster and registry.

## Non-Chaos experiment drivers

Some scenarios intentionally use ACR-native controls or workload load instead of a Chaos Studio fault.

| Scenario | Driver |
|---|---|
| B2 — ABAC mode flip | `acr-native/abac-modeflip.sh` |
| C1a — geo-routing exclusion | `acr-native/geo-failover-toggle.sh` |
| C1b — regional-endpoint failover | Enable regional endpoints and use explicit pull credentials or DNS-based routing; see `workloads/regional-endpoint-notes.md`. |
| D1/D2/D3 — throttling and tenant fairness | `workloads/pull-storm-job.yaml` and `workloads/tenant-fairness-*.yaml` |
| F3 — Artifact Cache upstream outage | `acr-native/setup-artifact-cache.sh` plus an upstream reachability break |

## Validation workflow

1. Confirm the environment is ready with `make preflight`.
2. Deploy with `make cycle`.
3. List experiments with `make experiments`.
4. Run the selected experiment with `make run EXP=<name>` or the scenario-specific driver.
5. Review `results/` and the corresponding file under `reports/`.
6. Tear down with `make reset`.
