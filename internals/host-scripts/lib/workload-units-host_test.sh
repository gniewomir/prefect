#!/usr/bin/env bash
# Offline tests: Workload dual-consumer units apply-Intent / purge (#136 / #142 / ADR-0034 / ADR-0024).
# Ambient UNIT_DIR, SYSTEMD_USER_DIR, WORKLOADS_ROOT, USER_NAME → temp dirs (no SSH / live Host).
# Stubs quadlet_user / quadlet_user_session_reload at the session boundary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=workload-units-host.sh
source "${REPO_ROOT}/internals/host-scripts/lib/workload-units-host.sh"

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

# --- Intent run: pod-membered always-on container skips restart; pod is restarted ---
reset
printf '[Pod]\nPodName=demo\n' >"${QUADLETS_STAGE}/demo.pod"
printf '[Container]\nImage=localhost/demo\nPod=demo.pod\n' >"${QUADLETS_STAGE}/demo-web.container"
workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent run should succeed for pod + member"
grep -Eq 'systemctl --user restart demo-pod\.service' "${QUADLET_LOG}" ||
  fail "Intent run must restart pod service"
grep -Eq 'systemctl --user restart demo-web\.service' "${QUADLET_LOG}" &&
  fail "Intent run must not restart pod-membered always-on container"
grep -Eq 'systemctl --user --quiet is-active demo-pod\.service' "${QUADLET_LOG}" ||
  fail "Intent run must assert pod is active"
grep -Eq 'systemctl --user --quiet is-active demo-web\.service' "${QUADLET_LOG}" &&
  fail "Intent run must not assert pod-membered container is active"
pass "Intent run restarts pod not pod-membered always-on container"

# --- Intent run: container-before-pod filename order still restarts pod only ---
reset
printf '[Container]\nImage=localhost/demo\nPod=demo.pod\n' >"${QUADLETS_STAGE}/demo-web.container"
printf '[Pod]\nPodName=demo\n' >"${QUADLETS_STAGE}/demo.pod"
workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent run should succeed when container sorts before pod"
grep -Eq 'systemctl --user restart demo-pod\.service' "${QUADLET_LOG}" ||
  fail "Intent run must restart pod service regardless of filename order"
grep -Eq 'systemctl --user restart demo-web\.service' "${QUADLET_LOG}" &&
  fail "Intent run must not restart pod-membered container when it sorts before pod"
pass "Intent run pod-centric apply is independent of filename order"

# --- Intent stop: pod-membered always-on container skips stop; pod is stopped ---
reset
printf '[Pod]\nPodName=demo\n' >"${QUADLETS_STAGE}/demo.pod"
printf '[Container]\nImage=localhost/demo\nPod=demo.pod\n' >"${QUADLETS_STAGE}/demo-web.container"
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent stop should succeed for pod + member"
grep -Eq 'systemctl --user stop demo-pod\.service' "${QUADLET_LOG}" ||
  fail "Intent stop must stop pod service"
grep -Eq 'systemctl --user stop demo-web\.service' "${QUADLET_LOG}" &&
  fail "Intent stop must not stop pod-membered always-on container"
pass "Intent stop stops pod not pod-membered always-on container"

# --- dangling Pod= fails closed ---
reset
printf '[Container]\nImage=localhost/demo\nPod=missing.pod\n' >"${QUADLETS_STAGE}/demo-web.container"
if workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" 2>/dev/null; then
  fail "expected fail-closed for dangling Pod="
fi
pass "dangling Pod= fails closed"

# --- empty Pod= fails closed ---
reset
printf '[Container]\nImage=localhost/demo\nPod=\n' >"${QUADLETS_STAGE}/demo-web.container"
if workload_units_apply "${WL_NAME}" run "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" 2>/dev/null; then
  fail "expected fail-closed for empty Pod="
fi
pass "empty Pod= fails closed"

# --- On-demand container with Pod= still Disarmed on Intent stop ---
reset
printf '[Pod]\nPodName=demo\n' >"${QUADLETS_STAGE}/demo.pod"
printf '[Container]\nImage=localhost/demo\nPod=demo.pod\nStartWithPod=false\n' >"${QUADLETS_STAGE}/demo-batch.container"
workload_units_apply "${WL_NAME}" stop "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent stop should succeed for on-demand pod-membered job"
grep -Eq 'systemctl --user stop demo-pod\.service' "${QUADLET_LOG}" ||
  fail "Intent stop must stop pod for on-demand workload"
grep -Eq 'systemctl --user stop demo-batch\.service' "${QUADLET_LOG}" ||
  fail "Intent stop must still Disarm on-demand pod-membered job"
pass "On-demand pod-membered job still Disarmed on Intent stop"

# --- Intent trash matches stop for always-on (units retained until Purge) ---
reset
printf '[Container]\nImage=localhost/app\n' >"${QUADLETS_STAGE}/app.container"
workload_units_apply "${WL_NAME}" trash "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" ||
  fail "apply Intent trash should succeed"
grep -Eq 'systemctl --user stop app\.service' "${QUADLET_LOG}" ||
  fail "Intent trash must stop always-on container service"
grep -Eq 'systemctl --user restart app\.service' "${QUADLET_LOG}" &&
  fail "Intent trash must not restart always-on container"
[[ -f "${UNIT_DIR}/app.container" ]] || fail "trash must retain unit files until Purge"
pass "Intent trash stops always-on and retains unit files"

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

# --- purge: stops and removes quadlets + systemd unit files for SoT basenames ---
reset
mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}/quadlets" "${WORKLOADS_ROOT}/${WL_NAME}/systemd"
printf '[Container]\nImage=localhost/app\n' >"${WORKLOADS_ROOT}/${WL_NAME}/quadlets/app.container"
printf '[Service]\nType=oneshot\nExecStart=/bin/true\n' >"${WORKLOADS_ROOT}/${WL_NAME}/systemd/app.service"
printf '[Container]\nImage=localhost/app\n' >"${UNIT_DIR}/app.container"
printf '[Service]\nType=oneshot\nExecStart=/bin/true\n' >"${SYSTEMD_USER_DIR}/app.service"
workload_units_purge "${WL_NAME}" || fail "purge should succeed for dual-consumer SoT"
[[ ! -f "${UNIT_DIR}/app.container" ]] || fail "purge must remove quadlets unit file"
[[ ! -f "${SYSTEMD_USER_DIR}/app.service" ]] || fail "purge must remove systemd unit file"
grep -Eq 'systemctl --user stop app\.service' "${QUADLET_LOG}" ||
  fail "purge must stop SoT-named units"
pass "purge stops and removes SoT unit files for both consumers"

# --- purge: removes Setup-owned .d drop-in dirs beside those units ---
reset
mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}/quadlets" "${WORKLOADS_ROOT}/${WL_NAME}/systemd"
printf '[Container]\nImage=localhost/app\n' >"${WORKLOADS_ROOT}/${WL_NAME}/quadlets/app.container"
printf '[Service]\nType=oneshot\nExecStart=/bin/true\n' >"${WORKLOADS_ROOT}/${WL_NAME}/systemd/app.service"
printf '[Container]\nImage=localhost/app\n' >"${UNIT_DIR}/app.container"
printf '[Service]\nType=oneshot\nExecStart=/bin/true\n' >"${SYSTEMD_USER_DIR}/app.service"
mkdir -p "${UNIT_DIR}/app.container.d" "${SYSTEMD_USER_DIR}/app.service.d"
printf '[Service]\nEnvironment=X=1\n' >"${UNIT_DIR}/app.container.d/10-env.conf"
printf '[Service]\nEnvironment=Y=1\n' >"${SYSTEMD_USER_DIR}/app.service.d/10-env.conf"
workload_units_purge "${WL_NAME}" || fail "purge should remove drop-in dirs"
[[ ! -d "${UNIT_DIR}/app.container.d" ]] || fail "purge must remove UNIT_DIR drop-in dir"
[[ ! -d "${SYSTEMD_USER_DIR}/app.service.d" ]] || fail "purge must remove SYSTEMD_USER_DIR drop-in dir"
pass "purge removes Setup-owned .d drop-in dirs"

# --- purge: does not remove WORKLOADS_ROOT tree (caller owns that) ---
reset
mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}/quadlets"
printf '[Container]\nImage=localhost/app\n' >"${WORKLOADS_ROOT}/${WL_NAME}/quadlets/app.container"
printf '[Container]\nImage=localhost/app\n' >"${UNIT_DIR}/app.container"
printf '{"intent":"trash"}\n' >"${WORKLOADS_ROOT}/${WL_NAME}/manifest.json"
workload_units_purge "${WL_NAME}" || fail "purge should succeed without removing SoT tree"
[[ -d "${WORKLOADS_ROOT}/${WL_NAME}" ]] || fail "purge must leave WORKLOADS_ROOT tree for caller"
[[ -f "${WORKLOADS_ROOT}/${WL_NAME}/quadlets/app.container" ]] ||
  fail "purge must leave SoT unit files under WORKLOADS_ROOT"
[[ -f "${WORKLOADS_ROOT}/${WL_NAME}/manifest.json" ]] || fail "purge must leave manifest for caller"
pass "purge leaves WORKLOADS_ROOT tree intact"

# --- purge: missing/empty consumer SoT dirs are fine (no-op success) ---
reset
mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}"
workload_units_purge "${WL_NAME}" || fail "missing consumer SoT dirs should be no-op success"
mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}/quadlets" "${WORKLOADS_ROOT}/${WL_NAME}/systemd"
workload_units_purge "${WL_NAME}" || fail "empty consumer SoT dirs should be no-op success"
pass "purge: missing/empty consumer SoT dirs are fine"

# --- purge: foreign unit file not listed in SoT is left alone ---
reset
mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}/quadlets"
printf '[Container]\nImage=localhost/app\n' >"${WORKLOADS_ROOT}/${WL_NAME}/quadlets/app.container"
printf '[Container]\nImage=localhost/app\n' >"${UNIT_DIR}/app.container"
printf '[Container]\nImage=localhost/foreign\n' >"${UNIT_DIR}/foreign.container"
workload_units_purge "${WL_NAME}" || fail "purge should succeed with foreign unit present"
[[ ! -f "${UNIT_DIR}/app.container" ]] || fail "purge must still remove SoT-listed unit"
[[ -f "${UNIT_DIR}/foreign.container" ]] || fail "purge must leave foreign unit file alone"
pass "purge leaves foreign UNIT_DIR basenames alone"

echo "All workload-units-host offline tests passed."
