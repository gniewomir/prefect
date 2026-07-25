# Park keeps Durables; Teardown is explicit full wipe

Stack iteration needed stable DNS and Host Volume bytes across teardown cycles (certs, Routes, ACME webroot). **Destroy** (remove every managed resource) was the wrong default. We replace it with **Park** (remove Host and other non-durables; keep **Durables**), **Apply** (create missing resources and reattach Durables; fail fast if Durable assumptions do not hold), and **Teardown** (full wipe including Durables). Durables are only the **Reserved IP** and the **Host Volume**. This supersedes ADR-0009’s “survive Host recreate, not Destroy” deferral — that need is now real.

**Operator UX:** `park.sh` is everyday iteration (warn that Durables still bill). `teardown.sh` requires typing `teardown` for the explicit full wipe.

**Terraform:** `lifecycle.prevent_destroy` on Durables (default on; must be a literal — Terraform cannot read a variable here). Teardown lifts the guard by writing a gitignored override (`durable_destroy_override.tf`) that sets `prevent_destroy = false` **and** passing `-var=allow_durable_destroy=true` (default false); a Stack precondition keeps those two aligned so raw destroy without both stays fail-closed. Reserved IP is split: address resource (Durable) + `digitalocean_reserved_ip_assignment` (non-durable, destroyed on Park, recreated on Apply). Host Volume stays a separate resource with `volume_ids` on the Host. Cloud Project must keep Durables assignable while Parked (unassigned Reserved IP must not drift to the account default — revisit ADR-0003’s “follow the Host” story for the Parked case).

**Tests:** Acceptance Tests stay non-destructive on an Applied Stack (Host present); they must not Park or Teardown. Lifecycle Tests (`lifecycle-test.sh`) are a separate opt-in suite for Park / Apply-after-Park / Teardown.

**Considered:** Redefine Destroy with a flag; compose-style up/down/teardown; keep Destroy as full wipe and add Park only; targets without `prevent_destroy`; `state rm` Durables. Rejected for accident risk, glossary collision with Workload **Purge**, or failing open on raw `terraform destroy`.
