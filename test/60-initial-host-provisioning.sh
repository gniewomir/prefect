#!/usr/bin/env bash
# Acceptance Test: Initial Host Provisioning finished
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

if ssh "${SSH_OPTS[@]}" "root@${IP}" "cloud-init status --wait" 2>/dev/null; then
  pass "Initial Host Provisioning finished"
else
  fail "Initial Host Provisioning wait failed on Host"
fi
