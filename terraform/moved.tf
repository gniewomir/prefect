# Reverse #25 indexed addresses: Park is State-gap, not count=0 desired config.
moved {
  from = digitalocean_tag.office[0]
  to   = digitalocean_tag.office
}

moved {
  from = digitalocean_tag.public_web[0]
  to   = digitalocean_tag.public_web
}

moved {
  from = digitalocean_ssh_key.web[0]
  to   = digitalocean_ssh_key.web
}

moved {
  from = digitalocean_droplet.web[0]
  to   = digitalocean_droplet.web
}

moved {
  from = digitalocean_reserved_ip_assignment.web[0]
  to   = digitalocean_reserved_ip_assignment.web
}

moved {
  from = digitalocean_firewall.public_web[0]
  to   = digitalocean_firewall.public_web
}
