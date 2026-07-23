# Edge, Service Network, and Workload Routes

Public Hosts get a mandatory **Edge** (Prefect-owned HTTP/HTTPS front door) and a Prefect-owned **Service Network**. Optional **Workloads** join that network and publish only through **Routes** (drop-in config the Edge includes). Unit names follow the role (`service-network`, `edge`, `edge-nginx`); tree is `prefect/network/` + `prefect/edge/`. TLS terminates at the Edge later (ACME sidecar in the Edge Pod); the first drop is HTTP :80 only, with Host bind mounts reserved for Routes and future certs. Empty Edge (no Routes) answers with a default 404/444 — not a holding page and not “don’t run.”

**Edge over peer Workloads on 80/443:** sole entrypoint is a Prefect invariant, not an accident of one container. Peer publishers would fight the Firewall/Reserved-IP story and ADR-0006’s rootless edge bind.

**Shared Service Network over one Pod for Edge+Workloads, host network, or Host-published Workload ports:** Workloads stay optional and independent; name-based reachability without exposing backends on the Host. The network is its own Prefect piece so Workloads do not depend on “nginx’s network.”

**Edge Pod + nginx container over a lone container:** reserves a sidecar slot for ACME without absorbing Workloads into the Pod. ACME itself is deferred; no placeholder/self-signed 443 in the first drop.

**Workload-owned Routes over a monolithic Edge config or dynamic discovery:** each Workload ships its fragment; the Edge is a shell. Reload-on-Route-change is a future deploy contract, not part of the first units. Alpine-family nginx image; Host bind mounts for Routes (and later certs).

**Unchanged from ADR-0004 / ADR-0006:** user Quadlets / rootless only; no Quadlet install in Initial Host Provisioning; Host stays a carrier.
