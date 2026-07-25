#!/usr/bin/env bash
# Lifecycle Test: Park → Apply preserves Durables (Reserved IP + Host Volume marker).
# Leftover Stack state on success: Applied (Host + Durables restored).
# On failure: may leave Parked or mid-Apply — restore with: ./apply.sh
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./lifecycle-test.sh)"
[[ -d "${STACK_DIR}" ]] || fail "missing Stack dir ${STACK_DIR}"

MARKER_PATH="/var/lib/prefect/lifecycle-park-apply.marker"
MARKER_BODY="lifecycle-park-apply-$(date -u +%Y%m%dT%H%M%SZ)-$$"

IP="$(stack_reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (Apply the Stack before this Lifecycle Test)"
export IP

wait_until_ssh_reachable
wait_until_volume_mounted

ssh "${SSH_OPTS[@]}" "root@${IP}" "printf '%s\n' '${MARKER_BODY}' > '${MARKER_PATH}'"
got="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat '${MARKER_PATH}'")"
[[ "${got}" == "${MARKER_BODY}" ]] || fail "marker write/read mismatch before Park"
pass "marker written on Host Volume"

echo "Parking Stack (confirming via stdin) ..."
printf 'park\n' | "${REPO_ROOT}/park.sh"

assert_reserved_ip_present "${IP}"
assert_volume_present

echo "Applying Stack after Park ..."
"${REPO_ROOT}/apply.sh" --yes

AFTER_IP="$(stack_reserved_ip)"
[[ "${AFTER_IP}" == "${IP}" ]] || fail "Reserved IP changed across Park→Apply: before=${IP} after=${AFTER_IP}"
pass "Reserved IP unchanged across Park→Apply (${IP})"

export IP="${AFTER_IP}"
ssh-keygen -R "${IP}" >/dev/null 2>&1 || true
wait_until_ssh_reachable
wait_until_volume_mounted

got="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat '${MARKER_PATH}' 2>/dev/null || true")"
[[ "${got}" == "${MARKER_BODY}" ]] || fail "marker missing or changed after Park→Apply (got: '${got}')"
pass "Host Volume marker survived Park→Apply"

pass "Park → Apply round-trip"
