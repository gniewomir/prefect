locals {
  # Twin of lib/ssh.sh PREFECT_SSH_PORT (ADR-0030).
  ssh_port = 9417
}

module "ihp_user_data" {
  source = "./cloud-init/render"

  volume_name = var.volume_name
  ssh_port    = local.ssh_port
}

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
    port_range       = tostring(local.ssh_port)
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
  size   = "s-1vcpu-1gb"
  image  = "ubuntu-26-04-x64"

  ipv6    = false
  backups = false

  ssh_keys = [digitalocean_ssh_key.web.fingerprint]
  tags = [
    digitalocean_tag.prefect.id,
    digitalocean_tag.public_web.id,
  ]

  # Initial Host Provisioning. Component Setup and Workloads remain outside it.
  # Host Volume attaches via digitalocean_volume_attachment so Park can detach
  # before Host destroy without DigitalOcean dropping Durable project membership.
  user_data = module.ihp_user_data.user_data
}

# This resource is the sole owner of Recreatable Cloud Project memberships.
resource "digitalocean_project_resources" "web_host" {
  project = var.project_id
  resources = [
    digitalocean_droplet.web.urn,
  ]
}

# Settle Host placement before droplet actions. DigitalOcean rejects concurrent
# droplet events, and reserved_ip_assignment create-then-read is flaky when the
# droplet still has a pending event.
resource "time_sleep" "before_droplet_actions" {
  depends_on = [digitalocean_project_resources.web_host]

  create_duration = "30s"
}

# Reserved IP before volume: one droplet action at a time, and Park still
# destroys volume attachment before Host membership/destroy so DigitalOcean
# cannot move the Durable volume out of the Cloud Project.
resource "digitalocean_reserved_ip_assignment" "web" {
  ip_address = var.reserved_ip_address
  droplet_id = digitalocean_droplet.web.id

  depends_on = [time_sleep.before_droplet_actions]
}

resource "digitalocean_volume_attachment" "web" {
  droplet_id = digitalocean_droplet.web.id
  volume_id  = var.volume_id

  depends_on = [digitalocean_reserved_ip_assignment.web]
}
