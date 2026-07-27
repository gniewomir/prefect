# Rename the project to Propraetor (deferred)

**Status:** accepted decision; execution deferred until deliberately scheduled.

The project name **Prefect** collides with [prefect.io](https://www.prefect.io/) (workflow orchestration). That collision is same-spelling and same broad “run infrastructure” neighborhood, so every search, README, and conversation pays a standing tax. We rename the project to **Propraetor** (*propraetor*: delegated provincial command on the same Roman magistracy ladder as *praefectus* / *legatus*). Rejected: keep Prefect; **Legate** (NVIDIA HPC runtime owns the name); other offices with live software brands (**Consul**, **Praetor**, **Praeses**, …). Etymology and glossary rewrite land with the rename — not before.

**Posture (ADR-0018):** one clean break. No dual-read of old/new names, no deprecation aliases, no “Prefect means Propraetor” shim. Callers, docs, Host identity, provider labels, and tests move in the same change (or a tightly sequenced cutover that leaves no half-life).

**Execution checklist** (abstract — re-discover concrete surfaces at rename time; do not treat path or file lists in the then-current tree as part of this ADR):

1. **Ubiquitous language** — Rewrite the project-name glossary entry and every domain term that embeds the old name (tags, user role, mount/layout concepts, Cloud Project labeling, etc.). Sweep `CONTEXT.md`, `docs/adr/`, agent docs, skills, and rules so prose and `_Avoid_` lists use Propraetor only.
2. **Operator surface** — Rename operator-facing identity: help text, script/CLI branding, Environment-scoped defaults that echo the project name, and any documented invocation examples.
3. **Host-local identity** — Move Host-side names that encode the project (system user, home/unit trees, Host Volume layout roots, Component/Workload trees under that root). Plan for Applied and Parked Environments; Durables that survive Park must still make sense after the rename.
4. **Provider-visible names** — Change account-unique labels derived from the project name (Cloud Project, tags, Firewall/Role selectors, resource name prefixes). Decide Adopt vs recreate vs Teardown+Apply per structural class so lifecycle convergence (ADR-0025 / ADR-0026) still holds; document the live cutover in a runbook *at execution time*.
5. **Contracts & fixtures** — Update Manifests, want-lists, Route/Quadlet assumptions, Acceptance Tests, Lifecycle Tests, and any golden strings that assert the old name.
6. **Repo & agent chrome** — Rename in-repo directories/packages whose *purpose* is the project brand (not every incidental string), Cursor/agent rules, issue/PR templates, and research docs that disambiguate against prefect.io (remove the disclaimer once obsolete).
7. **Verify** — On a disposable Environment: Apply / Park / Apply / Acceptance / Lifecycle matrix green under the new name; grep the workspace and a live Host for residual old-name tokens; confirm provider UI shows Propraetor-derived labels only.
8. **Close** — Single commit or short PR series with no transitional half-life; ADR titles that contain the old name may keep historical filenames — body text must use Propraetor after the sweep (optional follow-up: filename renames are cosmetic, not required for correctness).

**Out of scope until execution:** inventing compatibility bridges; renaming unrelated third-party tools; claiming domains/package names beyond what the operator surface needs.

**Revisit if:** a stronger unclaimed name on the same theme appears before execution, or an external contract has already stabilized on Prefect (then treat that surface as the ADR-0018 exception and ask before breaking it).
