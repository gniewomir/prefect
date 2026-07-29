# Shell twin of terraform/modules/recreatables local.ssh_port (ADR-0030).
# Sourced by operator SSH clients and Acceptance helpers. Keep the digit in sync
# with the Terraform local — mismatch locks the operator out.
# shellcheck disable=SC2034  # sourced constant; consumers use PREFECT_SSH_PORT
PREFECT_SSH_PORT=9417

# Reserved IP survives Host recreate; host keys do not. OpenSSH stores non-22
# ports as [host]:port — clearing only the bare IP leaves a stale entry that
# fails StrictHostKeyChecking=accept-new (accept-new does not replace mismatches).
prefect_ssh_forget_host() {
  local ip="${1:?prefect_ssh_forget_host requires IP}"
  ssh-keygen -R "${ip}" >/dev/null 2>&1 || true
  ssh-keygen -R "[${ip}]:${PREFECT_SSH_PORT}" >/dev/null 2>&1 || true
}
