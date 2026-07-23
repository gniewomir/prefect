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
# (volume.region must not reference the droplet).
resource "digitalocean_volume" "web" {
  region                  = "fra1"
  name                    = "prefect-web-data"
  size                    = 1
  initial_filesystem_type = "ext4"
  description             = "Host Volume for durable data surviving Host rebuilds (ADR-0009)"
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

  # Left-aligned: <<- only strips tabs; leading spaces break cloud-init detection.
  # Initial Host Provisioning: apt update + distro podman only (no package_upgrade);
  # unprivileged port floor for rootless 80/443 (ADR-0006); Prefect User + linger (ADR-0008).
  # No Quadlet units (ADR-0004 / ADR-0006) — Host stays a carrier.
  # Host Volume mount at /var/lib/prefect is deferred; attach only here (ADR-0009).
  user_data = <<-EOT
#cloud-config
ssh_pwauth: false
package_update: true
packages:
  - podman
users:
  - name: prefect
    lock_passwd: true
    shell: /bin/bash
write_files:
  - path: /etc/sysctl.d/99-unprivileged-port-start.conf
    content: |
      net.ipv4.ip_unprivileged_port_start=80
runcmd:
  - sysctl --system
  - loginctl enable-linger prefect
EOT
}

resource "digitalocean_reserved_ip" "web" {
  region     = digitalocean_droplet.web.region
  droplet_id = digitalocean_droplet.web.id
}
