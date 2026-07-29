# Environment declarations

Committed, Environment-scoped intent ([ADR-0033](../docs/adr/0033-environment-first-repo-layout.md); Domains: [ADR-0021](../docs/adr/0021-environment-domain-config.md)).

```text
environments/<cloud-slug>/domains.json
environments/<cloud-slug>/domains.override.json   # internal; gitignored (ADR-0021)
environments/<cloud-slug>/<workload-name>/          # directory = Workload (ADR-0033)
```

**Rule:** under `environments/<slug>/`, files are configuration or documentation; immediate non-hidden directories are Workload definition trees (identity = basename). Dotdirs are ignored. Workload directory internals are out of scope for ADR-0033.

**Workload Setup:** `./internals/workload-setup.sh [--env <slug>] <workload-name>` — name only; resolves under this tree (fail closed). Stack Apply does not run Workload Setup.

- **Cloud slug** — `test` (not Terraform workspace `default`), `prod`, … Same slug as Host naming (`prefect-test-…`).
- **Missing `domains.json`** — that Environment has zero Domains.
- **`domains.override.json`** — if present, replaces `domains.json` for all Domain-assignment readers. Not an operator surface; Lifecycle Tests only. See ADR-0021 / `internals/lifecycle-tests/README.md`.

JSON shape for Domains: map of apex FQDN → `{ "names": ["@", "www", …] }` (at least one label; each A → that Environment’s Reserved IP).
