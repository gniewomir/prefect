output "project_id" {
  value = digitalocean_project.prefect.id
}

output "reserved_ip_address" {
  value = digitalocean_reserved_ip.web.ip_address
}

output "volume_id" {
  value = digitalocean_volume.web.id
}

output "volume_name" {
  value = digitalocean_volume.web.name
}
