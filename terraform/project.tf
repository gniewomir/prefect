# Cloud Project Prefect owns assignable Stack resources.
# - Host + Host Volume: always listed when present in config.
# - Reserved IP: listed explicitly so an unassigned (Parked) address stays in Prefect
#   and does not drift to the account default (ADR-0003 / ADR-0016). When the IP is
#   assigned to the Host, the provider may also attach it via the Host; listing the
#   URN can show as floatingip in the Projects API — prefer refreshing/applying
#   rather than removing the URN (Parked membership is the priority).
resource "digitalocean_project" "prefect" {
  name        = "Prefect"
  description = "Prefect-managed projects infrastructure"
  purpose     = "Shared projects infrastructure"
  environment = "Production"
  is_default  = false

  resources = [
    digitalocean_droplet.web.urn,
    digitalocean_reserved_ip.web.urn,
    digitalocean_volume.web.urn,
  ]
}
