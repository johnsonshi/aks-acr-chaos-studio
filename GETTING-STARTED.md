# Getting started

Use this tutorial to deploy the sample environment, run a first AKS → ACR image-pull chaos experiment, inspect results, and tear everything down.

## Prerequisites

Install and sign in with the following tools:

- Azure CLI with Bicep support: `az version` and `az bicep version`
- `kubectl`
- `helm`
- `jq`
- `make`
- Bash

Azure requirements:

- Permission to create a resource group, AKS cluster, Premium ACR, network security group, Log Analytics workspace, role assignments, and Azure Chaos Studio resources.
- A VM SKU and region supported by the subscription.
- Registered resource providers, including `Microsoft.Chaos`.

Run the preflight check first:

```bash
make preflight
```

If a VM SKU is not available, choose another size or region:

```bash
az vm list-skus -l <region> --size <sku> -o table
```

## 1. Deploy the environment

`make cycle` creates the resource group, deploys AKS + ACR + supporting resources, deploys Chaos Studio targets and experiments, installs Chaos Mesh, seeds a test image, and renders workloads.

```bash
make cycle \
  RG=rg-acr-chaos \
  PREFIX=acrchaos \
  LOCATION=<region> \
  AKS_VM_SIZE=<sku>
```

Useful deployment options:

| Option | Example | Use |
|---|---|---|
| `LOCATION` | `eastus` | Azure region for the main deployment. |
| `AKS_VM_SIZE` | `Standard_D4s_v5` | Node size allowed by the subscription. |
| `AKS_ZONES` | `'["1","2","3"]'` | Enables a zone-pinned node pool for zone-loss scenarios. |
| `REPLICAS` | `'["westus3"]'` | ACR replica regions as a JSON array. |
| `ENABLE_CMK` | `true` | Adds CMK infrastructure for the Key Vault scenario. |

The deployment writes `.chaos.env` with resource names used by later targets. The file is gitignored.

## 2. Run the first experiment: A2 DNS failure

A2 is the recommended first run because it is fast, targeted, and does not require optional infrastructure.

```bash
make run EXP=acrchaos-a2-dns-failure
```

During the run, the Makefile:

1. Captures a baseline probe.
2. Starts the Azure Chaos Studio experiment.
3. Holds the fault for `HOLD_MIN` minutes.
4. Captures a during-fault probe.
5. Cancels the experiment.
6. Collects Log Analytics results.
7. Records a summary under `results/`.

What to look for:

- Targeted registry and MAR DNS names return `SERVFAIL` during the experiment.
- Non-targeted DNS names continue to resolve.
- Pull failures are visible as Kubernetes events or probe output while the fault is active.
- Resolution and pulls recover after the experiment is canceled.

A3 is the next recommended run:

```bash
make run EXP=acrchaos-a3-registry-latency-loss
```

## 3. Interpret results

Use three sources together:

| Source | Purpose |
|---|---|
| `results/<experiment>-<timestamp>/summary.md` | The raw run summary produced by `make run`. |
| `results/<experiment>-<timestamp>/probe-before.txt` and `probe-during.txt` | Baseline and during-fault reachability output. |
| [`reports/README.md`](reports/README.md) | Curated report index and current PASS/PARTIAL/BLOCKED/DOCUMENTED status. |

Outcome meanings:

- **PASS**: The scenario was exercised end-to-end and matched the documented hypothesis.
- **PARTIAL**: The run produced useful evidence but did not fully prove the hypothesis.
- **BLOCKED**: A platform, product, or environment constraint prevents the scenario from running as designed.
- **DOCUMENTED**: The item records a documented behavior or risk rather than an injectable experiment.

## 4. Run additional experiments

List deployed experiments:

```bash
make experiments
```

Run another Bicep-deployed experiment:

```bash
make run EXP=acrchaos-a3-registry-latency-loss
```

Other scenario types use additional steps:

| Scenario | How to run |
|---|---|
| Bicep-deployed Chaos experiments | `make run EXP=<experiment-name>` |
| B1 and C2 JSON experiments | See [experiments/README.md](experiments/README.md); these require extra target onboarding and are currently constrained on AKS-managed node pools. |
| B2 ABAC mode flip | Use `acr-native/abac-modeflip.sh` with a dedicated test registry and forced credential refresh. |
| C1a geo-routing toggle | Use `acr-native/geo-failover-toggle.sh exclude`, observe routing, then restore. |
| D1/D2/D3 load scenarios | Apply the pull-storm or tenant-fairness workloads against a dedicated registry. |
| F3 Artifact Cache | Configure the cache rule with `acr-native/setup-artifact-cache.sh`, then test upstream outage behavior. |

## 5. Run as a CI game day

The GitHub Actions workflow `.github/workflows/chaos-gameday.yml` can start a named experiment, wait, cancel it, and upload SLI output. It uses GitHub OIDC with Microsoft Entra ID, not stored Azure credentials.

One-time setup after the repository is pushed to GitHub:

```bash
GH_REPO=<owner>/<repo> RG=rg-acr-chaos bash scripts/setup-oidc.sh
```

The setup script creates a Microsoft Entra app registration and federated credential, grants Contributor on the resource group, and configures repository secrets and variables used by the workflow. Deploy `infra/chaos.bicep` locally with sufficient permissions before relying on CI, because that deployment creates role assignments.

## 6. Teardown

Delete Azure resources and local state:

```bash
make reset RG=rg-acr-chaos LOCATION=<region>
```

For non-CMK deployments, `make down` can start an asynchronous resource-group deletion. For CMK deployments, use `make reset` so the teardown script can also attempt purge cleanup for the soft-deleted vault.

## Troubleshooting

| Issue | Resolution |
|---|---|
| VM SKU or region is unavailable | Use `az vm list-skus -l <region> --size <sku> -o table`, choose an allowed SKU, or change `LOCATION`. |
| Provider registration fails or deployments cannot find Chaos resources | Run `bash scripts/00-prereqs.sh` or register required providers with `az provider register`. Registration can take several minutes. |
| Chaos Mesh faults do not start | Confirm `make prep` completed, `helm` installed Chaos Mesh, and target pods in the `chaos-pullers` namespace are healthy. |
| RBAC or role-assignment changes are not immediately effective | Wait for Azure role propagation, then retry. Token caching can also delay observable auth changes. |
| A2 DNS fault fails validation | Use exact FQDNs for registry and MAR names; invalid wildcard patterns can cause the full DNS fault to fail. |
| No Log Analytics rows appear | Confirm ACR Diagnostic settings route resource logs to the workspace and allow ingestion delay. |
| Public fallback masks a private endpoint test | Disable public network access when validating private endpoint or private DNS failure behavior. |

## Safety and cost

This sample is intended for disposable, non-production environments. It deliberately injects failures and creates billable Azure resources. Use short fault durations, dedicated test registries, scoped identities, and `make reset` when testing is complete.
