# Workload Intent modes and Purge

The Workload Manifest carries a **Workload Intent** (naming: ADR-0017): **run**, **stop**, or **trash**. **run** — Quadlets up; operator-authored Routes installed when present; HTTP semantics are whatever installed Routes declare. **stop** — no Quadlets; that Workload’s installed Routes removed (Edge default miss, not a Prefect 503); Workload data and Domain-scoped certificates preserved. **trash** — installed Routes removed; Workload data retained until **Purge**, which permanently deletes every Workload whose Intent is **trash** and Workload-associated data (installed Routes, Host Volume Workload tree, related units) — not Domains or Domain-scoped certificates (ADR-0022). Purge never touches Workloads whose Intent is **run** or **stop**. ACME want-list is Domain assignment (ADR-0023), not Manifest claims — Setup and Purge do not rebuild it.

**Intent stop uninstalls Routes (no Prefect 503):** process lifecycle parks without Prefect-owned Edge HTTP shells (Edge default miss — ADR-0022); Domain/certs stay.

**Intent trash + Purge over immediate delete on Manifest edit:** makes removal explicit and batchable.
