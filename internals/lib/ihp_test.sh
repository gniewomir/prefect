#!/usr/bin/env bash
# Unit tests: host_wait_until_ihp_done retries SSH 255 across ADR-0030 reboot.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=ihp.sh
source "${REPO_ROOT}/internals/lib/ihp.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

STUBS="$(mktemp -d "${TMPDIR:-/tmp}/ihp-op.XXXXXX")"
trap 'rm -rf "${STUBS}"' EXIT
SCRIPT="${STUBS}/wait.sh"
printf '#!/bin/true\n' >"${SCRIPT}"
chmod +x "${SCRIPT}"

CALLS="${STUBS}/calls"
: >"${CALLS}"

# Fail twice with 255, then succeed.
host_ssh() {
  local n
  n="$(wc -l <"${CALLS}" | tr -d ' ')"
  printf 'call\n' >>"${CALLS}"
  if [[ "${n}" -lt 2 ]]; then
    return 255
  fi
  return 0
}

export IHP_DONE_TIMEOUT_SECONDS=30
export IHP_DONE_RETRY_SECONDS=0
host_wait_until_ihp_done "${SCRIPT}" platform \
  || fail "should succeed after SSH 255 retries"
calls="$(wc -l <"${CALLS}" | tr -d ' ')"
[[ "${calls}" -eq 3 ]] || fail "expected 3 host_ssh attempts, got ${calls}"
pass "retries SSH exit 255 until success"

: >"${CALLS}"
host_ssh() {
  printf 'call\n' >>"${CALLS}"
  return 1
}
if host_wait_until_ihp_done "${SCRIPT}" platform; then
  fail "should fail closed on non-255 remote failure"
fi
calls="$(wc -l <"${CALLS}" | tr -d ' ')"
[[ "${calls}" -eq 1 ]] || fail "expected single attempt on exit 1, got ${calls}"
pass "does not retry non-255 failures"

echo "All host_wait_until_ihp_done checks passed."
