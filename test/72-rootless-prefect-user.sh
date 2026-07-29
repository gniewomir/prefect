#!/usr/bin/env bash
# Acceptance Test: rootless Prefect user exists with linger
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_host_session

USER_NAME="${PREFECT_USER:-prefect}"

# Standalone runs may race IHP; gate then assert linger (beyond carrier id check).
wait_until_carrier_ready

if ! host_ssh "id '${USER_NAME}'" >/dev/null 2>&1; then
  fail "Prefect user '${USER_NAME}' missing on Host"
fi

if ! linger="$(host_ssh "loginctl show-user '${USER_NAME}' -p Linger --value" 2>/dev/null)"; then
  fail "loginctl show-user ${USER_NAME} failed on Host"
fi

if [[ "${linger}" == "yes" ]]; then
  pass "Prefect user ${USER_NAME} exists with linger"
else
  fail "Prefect user ${USER_NAME} linger: expected yes, got '${linger}'"
fi
