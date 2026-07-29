# Environment config

Committed, Environment-scoped Stack intent outside the Terraform module ([ADR-0021](../docs/adr/0021-environment-domain-config.md)).

```text
config/environments/<cloud-slug>/domains.json
config/environments/<cloud-slug>/domains.override.json   # internal; gitignored (ADR-0021)
```

- **Cloud slug** — `test` (not Terraform workspace `default`), `prod`, … Same slug as Host naming (`prefect-test-…`).
- **Missing `domains.json`** — that Environment has zero Domains.
- **`domains.override.json`** — if present, replaces `domains.json` for all Domain-assignment readers. Not an operator surface; Lifecycle Tests only. See ADR-0021 / `internals/lifecycle-tests/README.md`.
- **Domains only for now** — other files may appear under the same slug later.

JSON shape: map of apex FQDN → `{ "names": ["@", "www", …] }` (at least one label; each A → that Environment’s Reserved IP).
