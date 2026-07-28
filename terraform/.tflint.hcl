# TFLint config for the Stack under terraform/.
# https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md
# Prefer a one-off: # tflint-ignore: rule_name  # why
# over widening this baseline.

config {
  call_module_type = "local"
  format           = "compact"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# --- Baseline: intentional for this monorepo Stack layout -------------------

# Exact provider / Terraform version pins live in terraform/versions.tf (and
# .terraform.lock.hcl). Local modules declare required_providers sources only.
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}
