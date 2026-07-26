# DigitalOcean Domains / DNS API (Durable design facts)

**Researched:** 2026-07-26  
**Question:** What does DigitalOcean’s Domains / DNS API actually provide for zone vs records, Cloud Project assignment, and Park/Teardown implications — enough to bound a Stack **Domain** Durable?

**Scope:** First-party DigitalOcean product docs and API/Terraform references only.

---

## Verdict

| Fact | Implication for Domain Durable |
| --- | --- |
| **Domain** = account DNS zone; **records** are separate child resources | Durable aggregate spans zone + Stack-authored `digitalocean_record`s; not one TF resource |
| Optional create-time `ip_address` mints an apex A outside a record resource | Prefer zone **without** `ip_address` + explicit record resources |
| Domains are project-assignable (`do:domain:{name}` / domain `urn`) | Same Cloud Project pattern as Reserved IP / Host Volume while Parked |
| Deleting a domain deletes its records | Teardown of the zone wipes managed and unmanaged records under it |
| Terraform tracks only declared `digitalocean_record`s | Manual edits to managed records = plan drift; UI-added extras = invisible until zone delete |
| Registrar must delegate NS to DigitalOcean | Stack cannot own registrar/NS; remains operator out of band |

---

## Zone vs records

DigitalOcean’s Domain resource is the zone: top-level control over a domain name managed in DO DNS. Individual DNS entries are Domain Record resources under that zone ([Domains API](https://docs.digitalocean.com/reference/api/reference/domains/), [Domain Records API](https://docs.digitalocean.com/reference/api/reference/domain-records/)).

Creating a domain: `POST /v2/domains` with `name`. Optional `ip_address` automatically creates an apex A ([Create a New Domain](https://docs.digitalocean.com/reference/api/reference/domains/)). The zone file / SOA is provider-managed; granular control is via record APIs.

Product docs: add domains with known ICANN TLDs; before use, [delegate NS to DigitalOcean](https://docs.digitalocean.com/products/networking/dns/how-to/add-domains/).

## Terraform mapping

- [`digitalocean_domain`](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/domain) — zone (`name`, optional `ip_address`); exports `id`, `urn`, `ttl`. Import by domain name.
- [`digitalocean_record`](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/record) — one resource per managed record (`domain`, `type`, `name`, `value`, …). Import as `domain,record_id`.

Drift: only resources in State are reconciled. Unmanaged records in the same zone do not appear on `digitalocean_domain` plans.

## Cloud Project assignment

Domains can be assigned to a project (Control Panel project picker on add; API via project resources and domain URN). Assignable independently of a Droplet/Host — suitable for Parked Environments that keep Domains + Reserved IP without a Host.

## Park / Teardown implications

- **Park:** Keep zone + Stack-authored records (and project assignment); no Host required for Domain presence.
- **Teardown:** Destroy Domain Durable (zone delete removes records). Registrar NS may still point at DO until the operator changes them — out of band.
- **Billing:** DO DNS itself is not a Reserved-IP-class billable line item in the same sense; Durable framing is still lifecycle/State ownership (Park keeps, Teardown removes), consistent with ADR-0016.

## Sources

- [How to Add Domains](https://docs.digitalocean.com/products/networking/dns/how-to/add-domains/)
- [Domains API](https://docs.digitalocean.com/reference/api/reference/domains/)
- [Domain Records API](https://docs.digitalocean.com/reference/api/reference/domain-records/)
- [Terraform digitalocean_domain](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/domain)
- [Terraform digitalocean_record](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/record)
