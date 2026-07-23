#!/usr/bin/env bash
# Acceptance Test: Initial Host Provisioning finished
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

# cloud-init ≥23.4: 0 = clean success, 2 = finished with recoverable errors
# (still "status: done"); 1 = crashed / not finished. Treat finished as pass.
set +e
ssh "${SSH_OPTS[@]}" "root@${IP}" "cloud-init status --wait" >/dev/null 2>&1
rc=$?
set -e
if [[ ${rc} -eq 0 || ${rc} -eq 2 ]]; then
  pass "Initial Host Provisioning finished"
else
  fail "Initial Host Provisioning wait failed on Host (exit ${rc})"
fi
