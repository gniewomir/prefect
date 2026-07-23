# Reserved IP follows the Host into this Cloud Project; do not list its URN
# (DigitalOcean Projects API still treats assigned Reserved IPs as floatingip and drifts).
resource "digitalocean_project" "prefect" {
  name        = "Prefect"
  description = "Prefect-managed projects infrastructure"
  purpose     = "Shared projects infrastructure"
  environment = "Production"
  is_default  = false

  resources = [digitalocean_droplet.web.urn]
}
