resource "digitalocean_tag" "office" {
  name = "prefect"
}

resource "digitalocean_tag" "public_web" {
  name = "prefect-public-web"
}

resource "digitalocean_ssh_key" "web" {
  name       = "prefect-web"
  public_key = var.DIGITALOCEAN_PUBLIC_KEY
}

# Host Volume before Host: volume_ids on the droplet must not create a region cycle
# (volume.region must not reference the droplet). Durable — Park keeps it; Teardown
# unlocks destroy via allow_durable_destroy + durable_destroy_override.tf (ADR-0016).
resource "digitalocean_volume" "web" {
  region                  = "fra1"
  name                    = "prefect-web-data"
  size                    = 1
  initial_filesystem_type = "ext4"
  description             = "Host Volume for durable data surviving Host rebuilds (ADR-0009)"

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_droplet" "web" {
  name   = "prefect-web"
  region = "fra1"
  size   = "s-1vcpu-512mb-10gb"
  image  = "ubuntu-26-04-x64"

  ipv6    = false
  backups = false

  ssh_keys = [digitalocean_ssh_key.web.fingerprint]
  tags = [
    digitalocean_tag.office.id,
    digitalocean_tag.public_web.id,
  ]
  volume_ids = [digitalocean_volume.web.id] # first apply may replace Host to attach at create

  # Initial Host Provisioning: apt update + distro podman only (no package_upgrade);
  # unprivileged port floor for rootless 80/443 (ADR-0006); Prefect User + linger (ADR-0008);
  # Host Volume mount at /var/lib/prefect (ADR-0009). No Quadlet units (ADR-0004 / ADR-0006).
  # cloud-config must stay left-aligned (#cloud-config at column 0).
  # Changing user_data replaces the Host; Host Volume reattaches via volume_ids.
  user_data = templatefile("${path.module}/cloud-init/web.yaml", {
    volume_name = digitalocean_volume.web.name
  })
}

# Reserved IP address (Durable): region only — not bound to Host lifecycle. Park keeps
# this object; assignment below is non-durable (ADR-0016). Region is a literal so the
# address does not depend on the Host (Park destroys the Host).
resource "digitalocean_reserved_ip" "web" {
  region = "fra1"

  lifecycle {
    prevent_destroy = true
  }
}

# Non-durable: destroyed on Park, recreated on Apply. Do not also set droplet_id on
# digitalocean_reserved_ip.web.
resource "digitalocean_reserved_ip_assignment" "web" {
  ip_address = digitalocean_reserved_ip.web.ip_address
  droplet_id = digitalocean_droplet.web.id
}
