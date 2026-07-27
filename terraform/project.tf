# Cloud Project Prefect owns assignable Stack resources.
# Host Volume + Domain stay on the project resource so they remain in Prefect while
# Parked and do not drift to the account default (ADR-0016).
#
# Reserved IP membership is a separate digitalocean_project_resources using the
# Projects API floatingip URN (not reservedip.urn) so refresh matches the provider
# and Apply does not 412 when moving an attached IP (ADR-0003). Park preserves this
# resource so the unassigned IP stays in Prefect (ADR-0016). It must not depend_on
# Park-destroyed addresses (Host assignment / IP assignment) — that would pull it
# into targeted destroy. Ordering: Host enters Prefect before IP is attached
# (see digitalocean_reserved_ip_assignment.web depends_on web_host).
#
# Host membership is a separate digitalocean_project_resources so Park can destroy the
# Host without pulling Cloud Project (and Durables) into the destroy graph. Apply
# recreates the Host assignment. Cloud Project itself is not a Durable.
resource "digitalocean_project" "prefect" {
  name        = local.names.project
  description = "Prefect-managed projects infrastructure"
  purpose     = "Shared projects infrastructure"
  environment = "Production"
  is_default  = false

  resources = concat(
    [
      digitalocean_volume.web.urn,
    ],
    [for d in digitalocean_domain.this : d.urn],
  )
}

resource "digitalocean_project_resources" "web_host" {
  project = digitalocean_project.prefect.id
  resources = [
    digitalocean_droplet.web.urn,
  ]
}

resource "digitalocean_project_resources" "reserved_ip" {
  project = digitalocean_project.prefect.id
  resources = [
    format("do:floatingip:%s", digitalocean_reserved_ip.web.ip_address),
  ]
}
