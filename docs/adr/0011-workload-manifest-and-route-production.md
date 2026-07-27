# Workload Manifest declares Intent; operator Routes are installed, not projected

A **Workload Manifest** is the source of truth for that Workload’s **Workload Intent** (ADR-0014 / ADR-0017). Optional interim **Public Hostnames** remain the ACME want-list input until a sibling cutover (unique among Intent **run**). **Routes** are operator-authored native config under `workloads/<name>/routes/`; Workload Setup installs them into the Edge routes directory as `<name>--<filename>` for Intent **run** and removes that Workload’s installed Routes for **stop** / **trash** — Prefect does not generate Edge shells or Manifest **interior** splicing (ADR-0022). ACME obtains one certificate per want-list name (HTTP-01); DNS remains out of band (A/AAAA → Reserved IP). Domain owns names and certificate material; a Workload uses them via Routes.

**Manifest Public Hostnames for ACME over parsing Route config:** keeps certificate input independent of proxy syntax until Domain-derived want-list.

**Operator-authored full Routes over generate-shell + optional interior:** Prefect stops owning Edge HTTP behaviour for Workloads; native nginx (or equivalent) stays the Workload HTTP language.

**Enumerated Public Hostnames + HTTP-01 over wildcards / DNS-01:** matches multiple domains and subdomains without DNS provider credentials on the Host (want-list SoT migrates in a sibling cutover).
