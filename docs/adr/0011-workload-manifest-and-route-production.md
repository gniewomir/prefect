# Workload Manifest declares Intent; operator Routes are installed, not projected

A **Workload Manifest** is the source of truth for that Workload’s **Workload Intent** (ADR-0014 / ADR-0017). It does not claim DNS names or feed ACME (want-list SoT: ADR-0023). **Routes** are operator-authored native config under `workloads/<name>/routes/`; Workload Setup installs them into the Edge routes directory as `<name>--<filename>` for Intent **run** and removes that Workload’s installed Routes for **stop** / **trash** — Prefect does not generate Edge shells or Manifest **interior** splicing (ADR-0022). ACME obtains one certificate per want-list name (HTTP-01); DNS for Domain-declared names is Stack-managed (ADR-0020 / ADR-0021). Domain owns names and certificate material; a Workload uses them via Routes.

**Operator-authored full Routes over generate-shell + optional interior:** Prefect stops owning Edge HTTP behaviour for Workloads; native nginx (or equivalent) stays the Workload HTTP language.

**Enumerated Domain FQDNs + HTTP-01 over wildcards / DNS-01:** matches multiple domains and subdomains without DNS provider credentials on the Host (ADR-0023).
