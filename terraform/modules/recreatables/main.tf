resource "digitalocean_tag" "prefect" {
  name = var.names.prefect_tag
}

resource "digitalocean_tag" "public_web" {
  name = var.names.role_tag
}

resource "digitalocean_ssh_key" "web" {
  name       = var.names.ssh_key
  public_key = var.public_key
}

resource "digitalocean_firewall" "public_web" {
  name = var.names.firewall
  tags = [digitalocean_tag.public_web.name]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0"]
  }
}

resource "digitalocean_droplet" "web" {
  name   = var.names.host
  region = var.region
  size   = "s-1vcpu-512mb-10gb"
  image  = "ubuntu-26-04-x64"

  ipv6    = false
  backups = false

  ssh_keys = [digitalocean_ssh_key.web.fingerprint]
  tags = [
    digitalocean_tag.prefect.id,
    digitalocean_tag.public_web.id,
  ]
  volume_ids = [var.volume_id]

  # Initial Host Provisioning. Component Setup and Workloads remain outside it.
  user_data = templatefile("${path.module}/cloud-init/web.yaml", {
    volume_name = var.volume_name
  })
}

# This resource is the sole owner of Recreatable Cloud Project memberships.
resource "digitalocean_project_resources" "web_host" {
  project = var.project_id
  resources = [
    digitalocean_droplet.web.urn,
  ]
}

# Host placement must complete before attachment. The reverse dependency order
# removes attachment before Host membership during Park.
resource "digitalocean_reserved_ip_assignment" "web" {
  ip_address = var.reserved_ip_address
  droplet_id = digitalocean_droplet.web.id

  depends_on = [digitalocean_project_resources.web_host]
}
