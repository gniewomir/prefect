#!/usr/bin/env bash
# Acceptance Test: Firewall inbound — ICMP allowed; TCP Prefect-SSH/80/443
# not filtered; classic :22 and TCP 25 filtered (ADR-0030).
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip

if ping -c 2 -W 5 "${IP}" >/dev/null 2>&1; then
  pass "inbound ICMP reaches Host"
else
  fail "inbound ICMP to ${IP} failed"
fi

for port in "${PLATFORM_SSH_PORT}" 80 443; do
  probe_allowed_tcp "${port}"
done

probe_denied_tcp 22
probe_denied_tcp 25
