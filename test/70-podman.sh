#!/usr/bin/env bash
# Acceptance Test: podman available on Host
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

if ssh "${SSH_OPTS[@]}" "root@${IP}" "podman --version" 2>/dev/null; then
  pass "podman available on Host"
else
  fail "podman --version failed on Host"
fi
