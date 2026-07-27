# Environment config

Committed, Environment-scoped Stack intent outside the Terraform module ([ADR-0021](../docs/adr/0021-environment-domain-config.md)).

```text
config/environments/<cloud-slug>/domains.json
```

- **Cloud slug** — `test` (not Terraform workspace `default`), `prod`, … Same slug as Host naming (`prefect-test-…`).
- **Missing `domains.json`** — that Environment has zero Domains.
- **Domains only for now** — other files may appear under the same slug later.

JSON shape: map of apex FQDN → `{ "names": ["@", "www", …] }` (at least one label; each A → that Environment’s Reserved IP).
