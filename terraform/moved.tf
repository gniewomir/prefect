# Indexed addresses for resources that Park removes (count = 0 when parked).
moved {
  from = digitalocean_tag.office
  to   = digitalocean_tag.office[0]
}

moved {
  from = digitalocean_tag.public_web
  to   = digitalocean_tag.public_web[0]
}

moved {
  from = digitalocean_ssh_key.web
  to   = digitalocean_ssh_key.web[0]
}

moved {
  from = digitalocean_droplet.web
  to   = digitalocean_droplet.web[0]
}

moved {
  from = digitalocean_reserved_ip_assignment.web
  to   = digitalocean_reserved_ip_assignment.web[0]
}

moved {
  from = digitalocean_firewall.public_web
  to   = digitalocean_firewall.public_web[0]
}
