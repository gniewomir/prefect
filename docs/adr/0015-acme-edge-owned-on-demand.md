# ACME is Edge-owned and on-demand

Certificate issuance and renewal are owned by the **Edge** Component, not by Workloads. ACME is **on-demand**, not a standing sidecar: Edge Component Setup always installs the ACME capability (oneshot unit, systemd user timer, Host Volume paths, HTTP-01 webroot shared with the Edge front door) even when the want-list is empty. A **systemd user timer** (Prefect User, linger) runs renewals periodically; Workload Setup may trigger an immediate run when Public Hostnames on Intent **run** change (non-blocking — ADR-0012). Renewal applies to Intent **run** want-list entries only — not Intent **stop** or **trash**. After issue/renew (and after oneshot runs that skip CA contact for fixtures), ACME **reloads** the Edge front door and does **not** generate or rewrite Workload Routes (ADR-0022). The Edge remains the sole publisher of :80/:443 — ACME writes challenge tokens and PEMs on the Host Volume for the front door to serve; it does not bind those ports itself. Automated paths default to the Let’s Encrypt **staging** directory; production is an explicit operator opt-in. Until a sibling cutover, want-list SoT remains Manifest Public Hostnames for Intent **run**.

**On-demand over a standing ACME sidecar in the Edge Pod:** matches idle cost and HTTP-01 webroot; refines ADR-0007’s reserved sidecar slot into a scheduled Edge job sharing volumes with nginx rather than an always-on Pod mate.

**Always-installed ACME capability over install-on-first-hostname:** keeps Edge Component shape complete; the want-list may be empty.

**systemd user timer over cron(8):** same Prefect User Quadlet path as the rest of the Edge; OnCalendar is a superset of typical cron schedules; Persistent/RandomizedDelay fit renewal; on-demand `systemctl --user start` shares the oneshot unit.

**Edge-owned ACME over Workload-owned ACME:** one issuer per Host; certificate material is Domain-scoped; Workloads declare interim Public Hostnames for the want-list only.
