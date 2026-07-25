variable "DIGITALOCEAN_PUBLIC_KEY" {
  type        = string
  description = "SSH public key for Host access. Set via TF_VAR_DIGITALOCEAN_PUBLIC_KEY."
}

variable "allow_durable_destroy" {
  type        = bool
  default     = false
  description = <<-EOT
    Teardown only: allow destroying Durables (Reserved IP address, Host Volume).
    Default false. Terraform cannot interpolate lifecycle.prevent_destroy, so Teardown
    must also write durable_destroy_override.tf (see durable_destroy_override.tf.example)
    before destroy; remove the override after. Raw destroy without both stays fail-closed.
  EOT
}

# Terraform requires prevent_destroy to be a literal; the unlock var alone cannot
# flip it. Align the operator-facing var with the override file Teardown writes.
# (check blocks only warn; precondition fails the plan.)
resource "terraform_data" "durable_destroy_unlock_gate" {
  input = var.allow_durable_destroy

  lifecycle {
    precondition {
      condition     = var.allow_durable_destroy == fileexists("${path.module}/durable_destroy_override.tf")
      error_message = <<-EOT
        allow_durable_destroy must match presence of durable_destroy_override.tf.
        Teardown writes the override and passes -var=allow_durable_destroy=true together;
        do not leave the unlock armed after Teardown. See durable_destroy_override.tf.example.
      EOT
    }
  }
}
