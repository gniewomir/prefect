# Workload Manifest produces Routes; names stay Manifest-owned

HTTPS needs enumerated **Public Hostnames** across many names on one Edge. A **Workload Manifest** is the source of truth for that Workload’s **Workload Intent** (ADR-0014 / ADR-0017), its Public Hostnames (one or more), and for producing its **Route**. Workload Setup generates the Edge server shell (listen / Public Hostnames / TLS wiring) from the Manifest; when no suitable generated proxy body applies, an optional Workload-provided **interior** may replace only the proxy body. The interior must not declare Public Hostnames — so Manifest and Route cannot drift without parsing proxy config. ACME obtains one certificate per declared Public Hostname (HTTP-01); DNS remains out of band (A/AAAA → Reserved IP). A Public Hostname is unique among Workloads on that Host that still claim it (Intent **run** or **stop**); Workload Setup fails on conflict. Intent **trash** releases the claim (ADR-0014).

**Manifest over parsing Route config for ACME:** keeps certificate input independent of proxy syntax.

**Generate shell + optional interior over hand-written full vhosts or Manifest-only with no escape hatch:** avoids hostname mismatch checks, still allows non-default proxy shape.

**Enumerated Public Hostnames + HTTP-01 over wildcards / DNS-01:** matches multiple domains and subdomains without DNS provider credentials on the Host.
