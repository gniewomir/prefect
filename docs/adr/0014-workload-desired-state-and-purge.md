# Workload Desired State and Purge

The Workload Manifest carries a **Workload Desired State**: **running**, **stopped**, or **trashed**. **running** — Quadlets up; Public Hostnames claimed; ACME renews; Edge proxies when the certificate exists. **stopped** — no Quadlets; Public Hostnames remain reserved; data and certificate material preserved; ACME does not renew; Edge does not proxy to the Workload and answers **503** for those names while a certificate can still terminate TLS; after certificate expiry the name goes dark (no HTTP status) until **running** issues a new certificate. First cut does not renew certificates while stopped. **trashed** — Public Hostnames released immediately; Workload data retained until **Purge**, which permanently deletes all trashed Workloads and associated data (Routes, certificates, Host Volume Workload data, related units). Purge never touches running or stopped Workloads.

**stopped holds names + 503 while the certificate lasts over releasing names, serving until expiry without 503, or renewing while stopped:** parks the Workload without giving up the Public Hostname; first cut accepts dark after expiry.

**trashed + Purge over immediate delete on Manifest edit:** makes removal explicit and batchable; names free for reclaim as soon as the Workload is trashed.
