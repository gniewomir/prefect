# Cloud Project Prefect owns assignable Stack resources.
# Durables (Reserved IP + Host Volume + Domain) stay on the project resource so they
# remain in Prefect while Parked and do not drift to the account default (ADR-0016).
# Listing an assigned Reserved IP can show as floatingip in the Projects API — prefer
# refresh/apply rather than removing the URN (Parked membership is the priority).
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
      digitalocean_reserved_ip.web.urn,
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
