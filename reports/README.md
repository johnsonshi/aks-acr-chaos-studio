# Experiment run reports

This directory indexes real runs of the AKS → ACR connectivity chaos scenarios against a Premium geo-replicated Azure Container Registry and AKS test environment. Each report records the scenario outcome, commands, and available evidence; individual experiment reports are not generated from assumed or fabricated results.

Run outcomes map to the capability tiers in the root README: **PASS** aligns with ✅ supported scenarios, **PARTIAL** usually indicates ⚙️ setup-or-scale work remains, **BLOCKED** aligns with ⛔ platform or environment constraints, and **DOCUMENTED** captures behavior that should be understood but is not directly injectable.

**Summary: 8 PASS · 6 PARTIAL · 5 BLOCKED · 1 DOCUMENTED (20 total).** PASS = A2, A3, A4, A5, B2, C1a, F1, F3. PARTIAL = A1, C1b, D1, D2, D3, F2.

| ID | Experiment | Report | Status |
|----|-----------|--------|--------|
| A1 | Registry unreachable (NSG) | [a1-nsg-block.md](a1-nsg-block.md) | ⚠️ PARTIAL |
| A2 | Registry DNS failure | [a2-dns-failure.md](a2-dns-failure.md) | ✅ PASS |
| A3 | Latency (delay) to registry | [a3-network-latency.md](a3-network-latency.md) | ✅ PASS |
| A4 | Data-endpoint-only outage | [a4-data-endpoint.md](a4-data-endpoint.md) | ✅ PASS |
| A5 | Private endpoint / DNS | [a5-private-endpoint.md](a5-private-endpoint.md) | ✅ PASS |
| B1 | IMDS / identity loss | [b1-imds-loss.md](b1-imds-loss.md) | 🚫 BLOCKED |
| B2 | ABAC mode flip | [b2-abac-flip.md](b2-abac-flip.md) | ✅ PASS |
| C1a | Geo-failover (ACR-native) | [c1a-geo-failover.md](c1a-geo-failover.md) | ✅ PASS |
| C1b | Regional-endpoint failover | [c1b-regional-failover.md](c1b-regional-failover.md) | ⚠️ PARTIAL |
| C1c | Global endpoint health-aware failover | [c1c-health-probe-gap.md](c1c-health-probe-gap.md) | 📄 DOCUMENTED |
| C2 | AKS availability-zone loss | [c2-az-loss.md](c2-az-loss.md) | 🚫 BLOCKED |
| D1 | Pull-storm throttling | [d1-throttling.md](d1-throttling.md) | ⚠️ PARTIAL |
| D2 | Tenant fairness | [d2-tenant-fairness.md](d2-tenant-fairness.md) | ⚠️ PARTIAL |
| D3 | Throttle during failover | [d3-throttle-failover.md](d3-throttle-failover.md) | ⚠️ PARTIAL |
| D4 | Disk pressure / GC | [d4-disk-pressure.md](d4-disk-pressure.md) | 🚫 BLOCKED |
| E1 | Node CPU/mem pressure | [e1-node-pressure.md](e1-node-pressure.md) | 🚫 BLOCKED |
| F1 | CMK registry with ACR→Key Vault access severed | [f1-cmk-keyvault.md](f1-cmk-keyvault.md) | ✅ PASS |
| F2 | MAR edge | [f2-mar-edge.md](f2-mar-edge.md) | ⚠️ PARTIAL |
| F3 | Artifact cache serves AKS when upstream unreachable | [f3-artifact-cache.md](f3-artifact-cache.md) | ✅ PASS |
| F4 | Connected-registry offline | [f4-connected-registry.md](f4-connected-registry.md) | 🚫 BLOCKED |
