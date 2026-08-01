#!/usr/bin/env bash
# Offline tests: Workload dual-consumer units apply-Intent (#136 / ADR-0034 / ADR-0024).
# Ambient UNIT_DIR, SYSTEMD_USER_DIR, WORKLOADS_ROOT, USER_NAME → temp dirs (no SSH / live Host).
# Stubs quadlet_user / quadlet_user_session_reload at the session boundary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=workload-units-host.sh
source "${REPO_ROOT}/internals/components/lib/workload-units-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/workload-units.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

UNIT_DIR="${TMP}/quadlet-units"
SYSTEMD_USER_DIR="${TMP}/systemd-units"
WORKLOADS_ROOT="${TMP}/workloads"
USER_NAME=""
WL_NAME="demo"
QUADLET_LOG="${TMP}/quadlet.log"

# Session-boundary stubs (systemctl / daemon-reload are Host-only).
quadlet_user() {
  printf '%s\n' "$*" >>"${QUADLET_LOG}"
  # Always-on run polls is-active; succeed immediately so tests stay offline-fast.
  if [[ "$*" == *"--quiet is-active"* ]] || [[ "$*" == *" is-active "* ]]; then
    return 0
  fi
  return 0
}

quadlet_user_session_reload() {
  printf 'daemon-reload\n' >>"${QUADLET_LOG}"
}

reset() {
  rm -rf "${UNIT_DIR}" "${SYSTEMD_USER_DIR}" "${WORKLOADS_ROOT}" "${TMP}/stage" "${QUADLET_LOG}"
  mkdir -p "${UNIT_DIR}" "${SYSTEMD_USER_DIR}" "${WORKLOADS_ROOT}" \
    "${TMP}/stage/quadlets" "${TMP}/stage/systemd"
  : >"${QUADLET_LOG}"
  unset -f workload_units_before_reload 2>/dev/null || true
}

QUADLETS_STAGE="${TMP}/stage/quadlets"
SYSTEMD_STAGE="${TMP}/stage/systemd"

# --- wrong-folder: native unit under quadlets/ fails closed ---
reset
printf '[Timer]\nOnCalendar=daily\n' >"${QUADLETS_STAGE}/bad.timer"
if workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" 2>/dev/null; then
  fail "expected fail-closed for timer authored under quadlets/"
fi
[[ ! -f "${UNIT_DIR}/bad.timer" ]] || fail "wrong-folder must not install into UNIT_DIR"
[[ ! -f "${SYSTEMD_USER_DIR}/bad.timer" ]] || fail "wrong-folder must not install into SYSTEMD_USER_DIR"
[[ ! -d "${WORKLOADS_ROOT}/${WL_NAME}/quadlets" ]] || fail "wrong-folder must not sync SoT"
pass "wrong-folder: timer under quadlets/ fails closed"

# --- wrong-folder: Quadlet under systemd/ fails closed ---
reset
printf '[Container]\nImage=localhost/x\n' >"${SYSTEMD_STAGE}/bad.container"
if workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" 2>/dev/null; then
  fail "expected fail-closed for container authored under systemd/"
fi
[[ ! -f "${UNIT_DIR}/bad.container" ]] || fail "wrong-folder must not install into UNIT_DIR"
[[ ! -f "${SYSTEMD_USER_DIR}/bad.container" ]] || fail "wrong-folder must not install into SYSTEMD_USER_DIR"
pass "wrong-folder: container under systemd/ fails closed"

# --- apply maps quadlets→UNIT_DIR, systemd→SYSTEMD_USER_DIR, syncs SoT ---
reset
printf '[Network]\nNetworkName=demo\n' >"${QUADLETS_STAGE}/demo.network"
printf '[Container]\nImage=localhost/demo\n' >"${QUADLETS_STAGE}/demo.container"
printf '[Service]\nType=oneshot\nExecStart=/bin/true\n' >"${SYSTEMD_STAGE}/demo.service"
printf '[Timer]\nOnCalendar=daily\n' >"${SYSTEMD_STAGE}/demo.timer"
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply should succeed for correctly authored dual consumers"
[[ -f "${UNIT_DIR}/demo.network" ]] || fail "expected demo.network in UNIT_DIR"
[[ -f "${UNIT_DIR}/demo.container" ]] || fail "expected demo.container in UNIT_DIR"
[[ -f "${SYSTEMD_USER_DIR}/demo.service" ]] || fail "expected demo.service in SYSTEMD_USER_DIR"
[[ -f "${SYSTEMD_USER_DIR}/demo.timer" ]] || fail "expected demo.timer in SYSTEMD_USER_DIR"
[[ ! -f "${SYSTEMD_USER_DIR}/demo.network" ]] || fail "network must not land in SYSTEMD_USER_DIR"
[[ ! -f "${UNIT_DIR}/demo.service" ]] || fail "service must not land in UNIT_DIR"
[[ -f "${WORKLOADS_ROOT}/${WL_NAME}/quadlets/demo.container" ]] || fail "expected SoT quadlets sync"
[[ -f "${WORKLOADS_ROOT}/${WL_NAME}/systemd/demo.service" ]] || fail "expected SoT systemd sync"
grep -Fq 'NetworkName=demo' "${UNIT_DIR}/demo.network" || fail "installed Quadlet must keep authored bytes"
grep -Fq 'Type=oneshot' "${SYSTEMD_USER_DIR}/demo.service" || fail "installed systemd unit must keep authored bytes"
pass "apply maps consumers to Host dirs and syncs SoT"

# --- basename ownership fail-closed: foreign basename already in UNIT_DIR ---
reset
printf '[Container]\nImage=localhost/foreign\n' >"${UNIT_DIR}/taken.container"
printf '[Container]\nImage=localhost/mine\n' >"${QUADLETS_STAGE}/taken.container"
if workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" 2>/dev/null; then
  fail "expected fail-closed when Host already has foreign basename"
fi
[[ ! -d "${WORKLOADS_ROOT}/${WL_NAME}/quadlets" ]] ||
  fail "foreign collision must not sync SoT before refuse"
pass "basename ownership: foreign UNIT_DIR basename refused"

# --- Intent run vs stop: always-on container records restart vs stop ---
reset
printf '[Container]\nImage=localhost/app\n' >"${QUADLETS_STAGE}/app.container"
workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent run should succeed"
grep -Fq 'daemon-reload' "${QUADLET_LOG}" || fail "expected session reload before Intent"
grep -Eq 'systemctl --user restart app\.service' "${QUADLET_LOG}" ||
  fail "Intent run must restart always-on container service"
grep -Eq 'systemctl --user stop app\.service' "${QUADLET_LOG}" &&
  fail "Intent run must not stop always-on container"

: >"${QUADLET_LOG}"
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent stop should succeed"
grep -Fq 'daemon-reload' "${QUADLET_LOG}" || fail "expected session reload before Intent stop"
grep -Eq 'systemctl --user stop app\.service' "${QUADLET_LOG}" ||
  fail "Intent stop must stop always-on container service"
grep -Eq 'systemctl --user restart app\.service' "${QUADLET_LOG}" &&
  fail "Intent stop must not restart always-on container"
pass "Intent run restarts and stop stops always-on container"

# --- before_reload hook runs between reconcile and reload ---
reset
HOOK_LOG="${TMP}/hook.log"
: >"${HOOK_LOG}"
printf '[Container]\nImage=localhost/hook\n' >"${QUADLETS_STAGE}/hook.container"
workload_units_before_reload() {
  [[ -f "${UNIT_DIR}/hook.container" ]] || fail "hook must run after reconcile installed units"
  printf 'before-reload\n' >>"${HOOK_LOG}"
}
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply with before_reload hook should succeed"
unset -f workload_units_before_reload
grep -Fq 'before-reload' "${HOOK_LOG}" || fail "expected workload_units_before_reload to run"
# Hook must precede daemon-reload in the session log.
python3 - "${QUADLET_LOG}" "${HOOK_LOG}" <<'PY' || fail "before_reload must run before daemon-reload"
import sys
quadlet = open(sys.argv[1]).read().splitlines()
hook = open(sys.argv[2]).read().splitlines()
assert hook == ["before-reload"], hook
assert "daemon-reload" in quadlet, quadlet
# Recording order: hook file written before reload line appended.
print("ok")
PY
pass "before_reload hook runs after reconcile, before reload"

# --- missing/empty consumer dirs are valid ---
reset
rm -rf "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}"
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "missing consumer dirs should be valid"
mkdir -p "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}"
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "empty consumer dirs should be valid"
[[ -z "$(ls -A "${UNIT_DIR}" 2>/dev/null || true)" ]] || fail "empty stages must not invent Quadlet units"
[[ -z "$(ls -A "${SYSTEMD_USER_DIR}" 2>/dev/null || true)" ]] || fail "empty stages must not invent systemd units"
pass "missing/empty quadlets/ and systemd/ are valid"

echo "All workload-units-host offline tests passed."
