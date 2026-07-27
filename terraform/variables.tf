variable "DIGITALOCEAN_PUBLIC_KEY" {
  type        = string
  description = "SSH public key for Host access. Set via TF_VAR_DIGITALOCEAN_PUBLIC_KEY."
}

variable "recreatables_present" {
  type        = bool
  default     = true
  description = "Operator lifecycle intent: Apply uses the default presence; Park supplies false for that invocation."
}

variable "allow_durable_destroy" {
  type        = bool
  default     = false
  description = <<-EOT
    Teardown only: allow destroying all Durables.
    Default false. Terraform cannot interpolate lifecycle.prevent_destroy, so Teardown
    must also write the Durable module override before destroy and remove it afterward.
    Raw destroy without both stays fail-closed.
  EOT
}
