# Domain Durable import — existing provider zone

ADR-0020 / ADR-0021 / ADR-0026 / issue #50. For a Domain **declared** in the Environment’s `domains.json`, ordinary **Apply** may **Adopt** an already-existing provider zone (exact FQDN match). Prefer that path.

This runbook is one-shot Stack surgery for cases Adopt does not cover or refuses. For a Domain that is **not** yet on the provider, use ordinary Apply: [add a new Domain](domain-durable-add.md).

Registrar NS → provider stays out of band and is unchanged by import.

## Before you start

1. Credentials set (`DIGITALOCEAN_TOKEN`; Apply also needs Operator Configuration key paths — see root `.env.example`).
2. Select the Environment workspace (raw `terraform` defaults to `default` = **test**; cloud slug for the config path is `test`).
3. Declare the Domain in that Environment’s file so Terraform expects it:

```text
environments/<slug>/domains.json
```

Example for **test**:

```json
{
  "example.com": {
    "names": ["@", "www"]
  }
}
```

`names` must match the Stack-authored A labels you will manage (at least one; A → Reserved IP). No `TF_VAR_domains` — the selected workspace loads this file.

4. Reserved IP must already be in State (or Apply will create Domains against a new address — usually wrong when adopting an existing zone pointed at an old IP).

## Import the zone

From the Stack directory (correct workspace already selected):

```bash
cd terraform
terraform import 'module.durables.digitalocean_domain.this["example.com"]' example.com
```

## Import Stack-authored A records

List record IDs on the provider:

```bash
doctl compute domain records list example.com
```

Import each label you declared in `names` (resource key is `zone:name`):

```bash
# Replace RECORD_ID with the A record id for @ / www / …
terraform import 'module.durables.digitalocean_record.a["example.com:@"]' 'example.com,RECORD_ID'
terraform import 'module.durables.digitalocean_record.a["example.com:www"]' 'example.com,RECORD_ID'
```

If a declared label has no A record yet, skip import for that key — the next Apply creates it.

## Converge

```bash
terraform plan
```

Expect updates so each imported A `value` matches the Environment Reserved IP (and Cloud Project membership). **Do not Apply** if the plan wants to **replace** or **destroy** the Domain zone unexpectedly.

```bash
terraform apply
```

After this, Park keeps the Domain; Teardown removes it with other Durables. No dual-path “create or adopt” in Apply — future collisions still fail closed.
