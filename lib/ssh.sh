# Shell twin of terraform/modules/recreatables local.ssh_port (ADR-0030).
# Sourced by operator SSH clients and Acceptance helpers. Keep the digit in sync
# with the Terraform local — mismatch locks the operator out.
# shellcheck disable=SC2034  # sourced constant; consumers use PREFECT_SSH_PORT
PREFECT_SSH_PORT=9417
