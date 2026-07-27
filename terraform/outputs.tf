output "reserved_ip" {
  description = "Public address of record for domains (ADR 0001). Point DNS here."
  value       = module.durables.reserved_ip_address
}
