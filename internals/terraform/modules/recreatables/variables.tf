variable "names" {
  description = "Provider names for Recreatable resources."
  type = object({
    propraetor_tag = string
    role_tag       = string
    host           = string
    firewall       = string
  })
}

variable "region" {
  description = "DigitalOcean region for the Host."
  type        = string
}

variable "host_root_ssh_public_key" {
  description = "Operator public key for root Host login via IHP (ADR-0037)."
  type        = string
}

variable "host_image" {
  description = "Host Image slug for the Droplet (override only for Lifecycle fault injection)."
  type        = string
  default     = "ubuntu-26-04-x64"
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
  description = "Durable Host Volume attached by Recreatable volume_attachment."
  type        = string
}

variable "volume_name" {
  description = "Durable Host Volume name used by Initial Host Provisioning."
  type        = string
}
