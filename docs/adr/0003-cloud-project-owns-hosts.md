---
status: superseded by ADR-0025
---

# Cloud Project owns Hosts; Reserved IP membership uses Projects API floatingip URN

The Stack creates Cloud Project `Propraetor` and assigns Hosts to it via a separate `digitalocean_project_resources` (so Park can destroy the Host without pulling the Cloud Project into the destroy graph).

A Reserved IP **attached** to a Host follows that Host’s Cloud Project at the provider. Explicit Cloud Project membership for the Reserved IP uses the Projects API shape `do:floatingip:<ip>` (not `digitalocean_reserved_ip.urn` / `do:reservedip:…`) — the API still reports assigned Reserved IPs as floatingip URNs, and assigning a `reservedip` URN while the IP is attached yields provider 412 (“move the Droplet instead”). Membership lives on Park-preserved `digitalocean_project_resources.reserved_ip`. That resource must not `depends_on` Park-destroyed addresses (Host or IP assignment), or targeted Park destroy would pull it into the destroy graph. Instead, the IP assignment waits until the Host is already in Propraetor so an attached IP follows the Host rather than being moved alone.

While **Parked**, the Reserved IP is unassigned: preserved `digitalocean_project_resources.reserved_ip` keeps it in Cloud Project `Propraetor` (with the Host Volume on the project resource) so it does not drift to the account default (ADR-0016).
