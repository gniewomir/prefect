---
status: accepted
---

# Adopt allowlisted provider facts into State during lifecycle commands

Amends ADR-0025’s operator convergence promise. Apply, Park, and Teardown must still converge by repeating the same normal operator command and must never require the operator to run imports, edit State, use targets, or perform provider-console surgery. Lifecycle commands may **Adopt**: bind an already-existing provider fact into State under the Environment’s known Stack-owned identity via preflight before the plan.

Adopt is allowlisted and exact-match only. Apply may Adopt identity-stable Durables (Domain, Host Volume, Cloud Project, Durable memberships) and known Recreatable relationships whose endpoints are already known (e.g. Reserved IP assignment when the IP and Host are in State). Park and Teardown may Adopt allowlisted Durables and Durable relationships only — not Recreatable presence. Ambiguity, wrong endpoint, identity conflict, unbound Host discovery, and orphan Reserved IP addresses (no Environment key without State) fail closed. Reactive Adopt after a failed apply is out of scope until evidence requires it.

This replaces Domain “name already exists → manual import runbook” as the normal path for declared Domains. One-shot surgery remains only for non-allowlisted orphans.

## Considered

Fail-closed forever on provider-has/State-missing (forces manual import; breaks hands-off Park→Apply when the provider flakes). Reactive-only Adopt without preflight (misses quiet gaps; still leaves “already assigned” traps unless failure parsing is perfect). Auto-Adopt of orphan Reserved IPs by region (unsafe identity). Rejected for now.
