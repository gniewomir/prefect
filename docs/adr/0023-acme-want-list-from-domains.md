# ACME want-list comes from Domain assignment, not Manifest claims

Edge ACME stays Edge-owned and on-demand (ADR-0015), but its want-list source of truth is the Environment’s committed Domain assignment (`environments/<slug>/domains.json`: each apex plus each `names` entry → FQDNs — ADR-0021 / ADR-0033), not Workload Manifest hostname claims. ensure-components derives that explicit FQDN set and installs the Host-local want-list; Edge Setup starts the ACME oneshot and waits for it to finish (front-door reload settles before Setup returns — ADR-0015); the existing timer renews every name on the want-list. Workload Setup and Purge no longer build or trigger ACME from Manifests. Manifest `public_hostnames` is removed in the same cutover (ADR-0018); the glossary term **Public Hostname** is deleted. ACME still Soft-fails DNS/CA problems (exit success after reload); Acceptance asserts certificate material when DNS answers at the Reserved IP. PEMs remain Edge-owned on the Host Volume; names leaving the want-list stop renewing but are not auto-deleted (Purge never deletes Domain-scoped certs — ADR-0022); Stack Teardown removes the volume. Wildcards / DNS-01 stay out (ADR-0011 preference). Delivery: [#44](https://github.com/gniewomir/prefect/issues/44).

**Domain `domains.json` FQDNs over live zone A/AAAA scan or Manifest claims:** reproducible, operator-visible managed names; avoids surprise certs and Workload↔name ownership.

**Operator-side want-list install over on-Host `domains.json` parse:** want-list stays the Host ACME contract; Edge does not learn the Propraetor config-tree layout.

**ensure-components oneshot + timer over Apply hook or Workload Setup trigger:** ACME stays with Edge bring-up; Stack Apply is not Host orchestration; Manifest claims are gone.

**Renew all want-list names over Intent/Route gating:** certificates are Domain-scoped; gating would reintroduce a fake claim map.

**No auto-delete PEMs on want-list shrink over prune-on-rebuild:** ordinary Apply cannot drop Domain names (`prevent_destroy`); stale PEMs must not race operator Routes; Teardown wipes the Host Volume.
