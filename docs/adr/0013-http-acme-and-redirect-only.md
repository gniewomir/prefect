# HTTP on the Edge is ACME and HTTPS redirect only

Once a Public Hostname has a certificate, :80 serves HTTP-01 challenges and redirects all other HTTP requests to HTTPS. The Edge never proxies a Workload over cleartext. Before the certificate exists, :80 may still serve ACME for that name; Workload traffic waits for HTTPS (ADR-0012). After redirect (or on :443), **running** proxies to the Workload; **stopped** returns 503 (ADR-0014).

**ACME + redirect over cleartext Workload serving:** preserves issuance/renewal and human `http://` links without weakening the TLS front door.
