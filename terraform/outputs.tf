output "reserved_ip" {
  description = "Public address of record for domains (ADR 0001). Point DNS here."
  value       = digitalocean_reserved_ip.web.ip_address
}
