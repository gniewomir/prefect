#!/usr/bin/env bash
# Acceptance Test: unprivileged port start allows rootless binds on 80/443
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

expected=80
actual="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sysctl -n net.ipv4.ip_unprivileged_port_start" 2>/dev/null || true)"
actual="$(echo "${actual}" | tr -d '[:space:]')"

if [[ "${actual}" == "${expected}" ]]; then
  pass "net.ipv4.ip_unprivileged_port_start is ${expected}"
else
  fail "net.ipv4.ip_unprivileged_port_start: expected ${expected}, got '${actual:-<empty>}'"
fi
