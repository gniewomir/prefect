#!/usr/bin/env bash
# Acceptance Test: net.ipv4.ip_unprivileged_port_start is 80
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

# Standalone runs may race IHP; gate then assert this capability slice.
wait_until_carrier_ready

expected=80
if ! actual="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sysctl -n net.ipv4.ip_unprivileged_port_start" 2>/dev/null)"; then
  fail "sysctl read of net.ipv4.ip_unprivileged_port_start failed on Host"
fi

if [[ "${actual}" == "${expected}" ]]; then
  pass "net.ipv4.ip_unprivileged_port_start is ${expected}"
else
  fail "net.ipv4.ip_unprivileged_port_start: expected ${expected}, got '${actual}'"
fi
