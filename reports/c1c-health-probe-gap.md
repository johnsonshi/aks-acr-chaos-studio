# C1c — Global endpoint health-aware failover (design note)

- **Status:** DOCUMENTED
- **Date (UTC):** 2026-07-07
- **Environment:** Premium geo-replicated ACR (global endpoint + one additional replica)
- **Injection mechanism:** Design note; true health-aware global-endpoint failover is not injectable from the client side
- **Capability mapping:** PASS = Supported; PARTIAL = Supported with caveats; BLOCKED = Not supported here or requires opt-in infrastructure; DOCUMENTED = Design note.
- **Demonstrates:** ACR global-endpoint failover is driven by service-side health detection, not by client-observable conditions such as HTTP `429` throttling.

## Design note

ACR's global endpoint routes clients through service-side health-aware routing. The health detection that drives a true global-endpoint failover is owned by the service and is not triggered by customer-side symptoms such as HTTP `429`, client throttling, local DNS changes, or client network blocks.

Because the trigger is service-side, a client cannot inject a true health-aware failover of the ACR global endpoint with Azure Chaos Studio or local workload pressure. A customer-side test can only observe the existing routing behavior or change customer-controlled routing inputs.

## What can be tested instead

You can mimic a failover by disabling or blocking a registry endpoint, then validating that clients use another path. Those are useful resilience tests, but they are not the same as a service-side health-aware failover:

- A1 blocks registry egress from the client side.
- A4 blocks the dedicated data-endpoint FQDN from the client side.
- C1a uses ACR's global-endpoint routing toggle to exclude a replica from routing.

These tests validate client behavior around endpoint loss or operator-directed routing. They do not prove that Traffic Manager's service-side health signal would declare a replica unhealthy under a client-observed condition such as `429`.

## Why it is not runnable here

Reproducing true health-aware failover would require a service-side condition that causes the global endpoint's health detection to mark a replica unhealthy. That cannot be produced from an AKS client, NSG rule, DNS fault, pull storm, or other customer-side injection in this sample.

## Client mitigation

Do not rely on being able to trigger service-side global-endpoint failover during a client game day. For hard regional isolation, design an explicit client failover path such as regional endpoints with appropriate credentials, DNS-based routing that preserves the expected registry hostname, or another controlled routing layer.

## Result

DOCUMENTED — a health-aware global-endpoint failover cannot be injected client-side. You can only mimic endpoint failover by disabling or blocking an endpoint, which is covered by other tests.
