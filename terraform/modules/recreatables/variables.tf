variable "names" {
  description = "Provider names for Recreatable resources."
  type = object({
    prefect_tag = string
    role_tag    = string
    ssh_key     = string
    host        = string
    firewall    = string
  })
}

variable "region" {
  description = "DigitalOcean region for the Host."
  type        = string
}

variable "public_key" {
  description = "SSH public key installed for operator access."
  type        = string
}

variable "project_id" {
  description = "Durable Cloud Project receiving Host membership."
  type        = string
}

variable "reserved_ip_address" {
  description = "Durable Reserved IP attached to the Host."
  type        = string
}

variable "volume_id" {
  description = "Durable Host Volume attached at Host creation."
  type        = string
}

variable "volume_name" {
  description = "Durable Host Volume name used by Initial Host Provisioning."
  type        = string
}
