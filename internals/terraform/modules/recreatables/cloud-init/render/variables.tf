variable "volume_name" {
  description = "Durable Host Volume name used by Initial Host Provisioning."
  type        = string
}

variable "ssh_port" {
  description = "SSH listen port written into IHP sshd_config Port drop-in."
  type        = number
}
