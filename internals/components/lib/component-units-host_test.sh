#!/usr/bin/env bash
# Offline tests: Component dual-consumer unit install (#130 / ADR-0034 / ADR-0010).
# Ambient UNIT_DIR, SYSTEMD_USER_DIR, USER_NAME → temp dirs (no SSH / live Host).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=component-units-host.sh
source "${REPO_ROOT}/internals/components/lib/component-units-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/component-units.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

UNIT_DIR="${TMP}/quadlet-units"
SYSTEMD_USER_DIR="${TMP}/systemd-units"
USER_NAME="offline-test-user"
TREE="${TMP}/component"
mkdir -p "${UNIT_DIR}" "${SYSTEMD_USER_DIR}"

reset_tree() {
  rm -rf "${TREE}" "${UNIT_DIR}" "${SYSTEMD_USER_DIR}"
  mkdir -p "${UNIT_DIR}" "${SYSTEMD_USER_DIR}" "${TREE}/quadlets" "${TREE}/systemd"
}

# --- wrong-folder: native unit under quadlets/ fails closed ---
reset_tree
printf '[Timer]\nOnCalendar=daily\n' >"${TREE}/quadlets/bad.timer"
if component_units_install "${TREE}" 2>/dev/null; then
  fail "expected fail-closed for timer authored under quadlets/"
fi
[[ ! -f "${UNIT_DIR}/bad.timer" ]] || fail "wrong-folder must not install into UNIT_DIR"
[[ ! -f "${SYSTEMD_USER_DIR}/bad.timer" ]] || fail "wrong-folder must not install into SYSTEMD_USER_DIR"
pass "wrong-folder: timer under quadlets/ fails closed"

# --- wrong-folder: Quadlet under systemd/ fails closed ---
reset_tree
printf '[Container]\nImage=localhost/x\n' >"${TREE}/systemd/bad.container"
if component_units_install "${TREE}" 2>/dev/null; then
  fail "expected fail-closed for container authored under systemd/"
fi
[[ ! -f "${UNIT_DIR}/bad.container" ]] || fail "wrong-folder must not install into UNIT_DIR"
[[ ! -f "${SYSTEMD_USER_DIR}/bad.container" ]] || fail "wrong-folder must not install into SYSTEMD_USER_DIR"
pass "wrong-folder: container under systemd/ fails closed"

# --- install maps quadlets/ → UNIT_DIR and systemd/ → SYSTEMD_USER_DIR ---
reset_tree
printf '[Network]\nNetworkName=demo\n' >"${TREE}/quadlets/demo.network"
printf '[Pod]\nPodName=demo\n' >"${TREE}/quadlets/demo.pod"
printf '[Service]\nType=oneshot\nExecStart=/bin/true\n' >"${TREE}/systemd/demo.service"
printf '[Timer]\nOnCalendar=daily\n' >"${TREE}/systemd/demo.timer"
component_units_install "${TREE}" || fail "install should succeed for correctly authored dual consumers"
[[ -f "${UNIT_DIR}/demo.network" ]] || fail "expected demo.network in UNIT_DIR"
[[ -f "${UNIT_DIR}/demo.pod" ]] || fail "expected demo.pod in UNIT_DIR"
[[ -f "${SYSTEMD_USER_DIR}/demo.service" ]] || fail "expected demo.service in SYSTEMD_USER_DIR"
[[ -f "${SYSTEMD_USER_DIR}/demo.timer" ]] || fail "expected demo.timer in SYSTEMD_USER_DIR"
[[ ! -f "${SYSTEMD_USER_DIR}/demo.network" ]] || fail "network must not land in SYSTEMD_USER_DIR"
[[ ! -f "${UNIT_DIR}/demo.service" ]] || fail "service must not land in UNIT_DIR"
grep -Fq 'NetworkName=demo' "${UNIT_DIR}/demo.network" || fail "installed Quadlet must keep authored bytes"
grep -Fq 'Type=oneshot' "${SYSTEMD_USER_DIR}/demo.service" || fail "installed systemd unit must keep authored bytes"
pass "install maps quadlets/ → UNIT_DIR and systemd/ → SYSTEMD_USER_DIR"

# --- missing/empty consumer dirs are valid ---
rm -rf "${TREE}" "${UNIT_DIR}" "${SYSTEMD_USER_DIR}"
mkdir -p "${UNIT_DIR}" "${SYSTEMD_USER_DIR}" "${TREE}"
component_units_install "${TREE}" || fail "missing consumer dirs should be valid"
mkdir -p "${TREE}/quadlets" "${TREE}/systemd"
component_units_install "${TREE}" || fail "empty consumer dirs should be valid"
[[ -z "$(ls -A "${UNIT_DIR}" 2>/dev/null || true)" ]] || fail "empty tree must not invent Quadlet units"
[[ -z "$(ls -A "${SYSTEMD_USER_DIR}" 2>/dev/null || true)" ]] || fail "empty tree must not invent systemd units"
pass "missing/empty quadlets/ and systemd/ are valid"

# --- only quadlets/ (Service Network shape) installs without systemd/ ---
reset_tree
rm -rf "${TREE}/systemd"
printf '[Network]\nNetworkName=service-network\n' >"${TREE}/quadlets/service-network.network"
component_units_install "${TREE}" || fail "quadlets-only Component should install"
[[ -f "${UNIT_DIR}/service-network.network" ]] || fail "expected service-network.network installed"
[[ -z "$(ls -A "${SYSTEMD_USER_DIR}" 2>/dev/null || true)" ]] || fail "quadlets-only must not invent systemd units"
pass "quadlets-only Component installs without systemd/"

echo "All component-units-host offline tests passed."
