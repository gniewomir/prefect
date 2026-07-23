#!/usr/bin/env bash
# Acceptance Test: outbound HTTPS from Host
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

if ssh "${SSH_OPTS[@]}" "root@${IP}" "curl -fsS -o /dev/null -w '%{http_code}' --connect-timeout 10 https://example.com" 2>/dev/null | grep -Eq '^[23][0-9][0-9]$'; then
  pass "outbound HTTPS from Host"
else
  fail "outbound HTTPS smoke from Host failed"
fi
