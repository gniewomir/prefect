# Domain Durable import — existing provider zone

ADR-0020 / issue #50. **Apply does not auto-adopt** a Domain that already exists on the provider (“name already exists”). Use this one-shot Stack surgery, then ordinary Apply/Park/Teardown.

Registrar NS → provider stays out of band and is unchanged by import.

## Before you start

1. Credentials set (`DIGITALOCEAN_TOKEN`, `TF_VAR_DIGITALOCEAN_PUBLIC_KEY`).
2. Select the Environment workspace (raw `terraform` defaults to `default` = **test**).
3. Put the Domain in Stack config so Terraform expects it — e.g. `TF_VAR_domains` JSON:

```bash
export TF_VAR_domains='{"example.com":{"names":["@","www"]}}'
```

`names` must match the Stack-authored A labels you will manage (at least one; A → Reserved IP).

4. Reserved IP must already be in State (or Apply will create Domains against a new address — usually wrong when adopting an existing zone pointed at an old IP).

## Import the zone

From the Stack directory:

```bash
cd terraform
terraform import 'digitalocean_domain.this["example.com"]' example.com
```

## Import Stack-authored A records

List record IDs on the provider:

```bash
doctl compute domain records list example.com
```

Import each label you declared in `names` (resource key is `zone:name`):

```bash
# Replace RECORD_ID with the A record id for @ / www / …
terraform import 'digitalocean_record.a["example.com:@"]' 'example.com,RECORD_ID'
terraform import 'digitalocean_record.a["example.com:www"]' 'example.com,RECORD_ID'
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
