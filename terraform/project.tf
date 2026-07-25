# Cloud Project Prefect owns assignable Stack resources.
# - Always: Host Volume + Reserved IP URN. Listing the address keeps an unassigned
#   (Parked) IP in Prefect instead of the account default (ADR-0016). When the IP is
#   assigned to the Host, the provider may also attach it via the Host; listing the
#   URN can show as floatingip in the Projects API — prefer refreshing/applying
#   rather than removing the URN (Parked membership is the priority). Removing an
#   assigned Reserved IP from the project fails at the API (move the Host instead).
# - Applied only: Host URN. Parked: Host absent; Durables stay listed.
# Cloud Project itself is not a Durable but remains while Parked so membership holds.
resource "digitalocean_project" "prefect" {
  name        = "Prefect"
  description = "Prefect-managed projects infrastructure"
  purpose     = "Shared projects infrastructure"
  environment = "Production"
  is_default  = false

  resources = concat(
    var.parked ? [] : [digitalocean_droplet.web[0].urn],
    [
      digitalocean_reserved_ip.web.urn,
      digitalocean_volume.web.urn,
    ],
  )
}
