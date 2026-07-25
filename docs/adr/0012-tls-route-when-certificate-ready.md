# Enable TLS Route shell only after the certificate exists

For each Public Hostname, the Edge enables the HTTPS server shell only once the corresponding certificate is present on the Host Volume. Workload Setup projects the Workload Manifest (Workload Intent, Public Hostname claim, ACME request, optional Route interior) and must not block on issuance — DNS is out of band and happy-path ACME is usually seconds to a couple of minutes, but mispointed DNS makes wait time unbounded. “HTTPS live” is a readiness/Acceptance concern, not a Workload Setup success criterion. When Intent is **stop**, the same TLS shell is used to return 503 without proxying (ADR-0014) — still only while a usable certificate exists.

**Enable-when-ready over immediate :443 with broken handshakes:** avoids serving a Public Hostname on HTTPS before TLS can succeed.

**Non-blocking Setup over Setup-waits-for-cert:** keeps Workload Setup deterministic when DNS or CAA is wrong.
