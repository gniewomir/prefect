#!/usr/bin/env bash
# Lifecycle Test: Teardown wipes Durables (Reserved IP + Host Volume) and empties State.
# Leftover Stack state on success: empty (no managed addresses; Durables gone at provider).
# On failure: may leave Applied, Parked, or mid-Teardown — restore with:
#   Prefer Park if Durables remain; full wipe: ./teardown.sh; then ./apply.sh.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./lifecycle-test.sh)"
[[ -d "${STACK_DIR}" ]] || fail "missing Stack dir ${STACK_DIR}"

IP="$(stack_reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (Apply the Stack before this Lifecycle Test)"

assert_reserved_ip_present "${IP}"
assert_volume_present

echo "Tearing down Stack (confirming via stdin) ..."
printf 'teardown\n' | "${REPO_ROOT}/teardown.sh" --env "${PREFECT_ENV}"

assert_reserved_ip_absent "${IP}"
assert_volume_absent
assert_stack_empty

pass "Teardown wiped Durables and emptied Stack"
