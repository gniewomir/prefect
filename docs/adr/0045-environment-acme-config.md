# Environment ACME config is committed acme.json

Edge ACME’s Let’s Encrypt directory (`production` | `staging`) and contact email are declared in committed `environments/<cloud-slug>/acme.json`, staged by ensure-components onto the Host as an EnvironmentFile for `edge-acme.service` (same handoff shape as the Domain-derived want-list — ADR-0023). Missing file means staging with no email line (Host still derives `acme@<apex>` per acme-run). Present file requires both keys and fail-closes on bad shape. This is the explicit production opt-in ADR-0015 required — not Environment Configuration (ADR-0035; Components do not consume that bag) and not a field on `domains.json`.

**Committed Environment file over `.env` / shell exports / extending domains.json:** keeps CA choice and contact as reviewable Environment intent beside Domain assignment; avoids secret-bag and Domain-Durable conflation.
