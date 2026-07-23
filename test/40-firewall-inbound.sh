#!/usr/bin/env bash
# Acceptance Test: Firewall inbound — ICMP allowed; TCP 22/80/443 not filtered; TCP 25 filtered
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip

if ping -c 2 -W 5 "${IP}" >/dev/null 2>&1; then
  pass "inbound ICMP reaches Host"
else
  fail "inbound ICMP to ${IP} failed"
fi

for port in 22 80 443; do
  probe_allowed_tcp "${port}"
done

# Denied TCP: Firewall should DROP (timeout), not allow through to a closed port (refused).
set +e
DENY_OUT="$(probe_tcp_nc 25)"
DENY_RC=$?
set -e
if [[ ${DENY_RC} -eq 0 ]]; then
  fail "inbound TCP 25 unexpectedly accepted"
elif echo "${DENY_OUT}" | grep -qi "refused"; then
  fail "inbound TCP 25 reached Host (connection refused) — Firewall likely allowing it"
else
  pass "inbound TCP 25 filtered (denied by Firewall)"
fi
