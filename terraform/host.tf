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

  # Left-aligned: <<- only strips tabs; leading spaces break cloud-init detection.
  # Initial Host Provisioning: apt update + distro podman only (no package_upgrade).
  user_data = <<-EOT
#cloud-config
ssh_pwauth: false
package_update: true
packages:
  - podman
EOT
}

resource "digitalocean_reserved_ip" "web" {
  region     = digitalocean_droplet.web.region
  droplet_id = digitalocean_droplet.web.id
}
