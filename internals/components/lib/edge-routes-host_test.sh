#!/usr/bin/env bash
# Unit tests: Workload Route reconcile, multi-Workload gather, want-list fail-closed
# (ADR-0028 / ADR-0040). No cloud Apply — temp dirs only.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=edge-routes-host.sh
source "${REPO_ROOT}/internals/components/lib/edge-routes-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/edge-routes.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

ROUTES_DIR="${TMP}/routes"
WANT_LIST="${TMP}/want-list"
SOT="${TMP}/sot"
mkdir -p "${ROUTES_DIR}" "${SOT}"
printf '%s\n' 'alpha.example.test' >"${WANT_LIST}"

# --- Intent run fails closed when Route basename is not on the want-list ---
printf '%s\n' 'location / { return 200 "x"; }' >"${SOT}/not-on-list.example.test.conf"
if edge_reconcile_workload_routes "wl" "run" "${SOT}" 2>/dev/null; then
  fail "expected fail-closed for Route basename not on want-list"
fi
[[ ! -f "${ROUTES_DIR}/wl--not-on-list.example.test.conf" ]] \
  || fail "fail-closed must not install off-want-list Route"
pass "Intent run fails closed when Route basename is not on the want-list"

# --- Intent run installs FQDN-keyed fragment when basename is on the want-list ---
rm -rf "${SOT}"
mkdir -p "${SOT}"
printf '%s\n' 'location /probe { return 200 "ok"; }' >"${SOT}/alpha.example.test.conf"
edge_reconcile_workload_routes "wl" "run" "${SOT}"
[[ -f "${ROUTES_DIR}/wl--alpha.example.test.conf" ]] \
  || fail "expected installed wl--alpha.example.test.conf"
grep -Fq 'location /probe' "${ROUTES_DIR}/wl--alpha.example.test.conf" \
  || fail "installed Route must keep operator fragment bytes"
pass "Intent run installs FQDN-keyed fragment when basename is on the want-list"

# --- Fail-closed leaves a prior good install untouched ---
printf '%s\n' 'location /bad { return 200 "bad"; }' >"${SOT}/off.example.test.conf"
if edge_reconcile_workload_routes "wl" "run" "${SOT}" 2>/dev/null; then
  fail "expected fail-closed when SoT mixes on- and off-want-list basenames"
fi
[[ -f "${ROUTES_DIR}/wl--alpha.example.test.conf" ]] \
  || fail "prior good install must remain after fail-closed"
[[ ! -f "${ROUTES_DIR}/wl--off.example.test.conf" ]] \
  || fail "off-want-list Route must not be installed"
pass "fail-closed leaves a prior good install untouched"

# --- Intent stop removes that Workload's installed Routes ---
edge_reconcile_workload_routes "wl" "stop" "${SOT}"
[[ ! -f "${ROUTES_DIR}/wl--alpha.example.test.conf" ]] \
  || fail "Intent stop must remove installed Routes"
pass "Intent stop removes that Workload's installed Routes"

# --- Zero Routes (missing/empty sot) is valid for Intent run ---
rm -rf "${SOT}"
edge_reconcile_workload_routes "empty" "run" "${SOT}"
edge_reconcile_workload_routes "empty" "run" ""
pass "zero Routes is valid for Intent run"

# --- Other Workloads' installs are not removed on stop ---
printf '%s\n' '# other' >"${ROUTES_DIR}/other--alpha.example.test.conf"
mkdir -p "${SOT}"
printf '%s\n' 'location /a { return 200 "a"; }' >"${SOT}/alpha.example.test.conf"
edge_reconcile_workload_routes "wl" "run" "${SOT}"
edge_reconcile_workload_routes "wl" "stop" "${SOT}"
[[ -f "${ROUTES_DIR}/other--alpha.example.test.conf" ]] \
  || fail "stop must not remove another Workload's Routes"
pass "stop does not remove another Workload's installed Routes"

# --- gather-all: Intent-run Declarations across Workloads ---
WL_ROOT="${TMP}/workloads-gather"
rm -rf "${WL_ROOT}" "${ROUTES_DIR}"
mkdir -p "${ROUTES_DIR}" \
  "${WL_ROOT}/alpha/routes" \
  "${WL_ROOT}/beta/routes"
printf '%s\n' '{"intent":"run"}' >"${WL_ROOT}/alpha/manifest.json"
printf '%s\n' '{"intent":"run"}' >"${WL_ROOT}/beta/manifest.json"
printf '%s\n' 'location /a { return 200 "a"; }' >"${WL_ROOT}/alpha/routes/alpha.example.test.conf"
printf '%s\n' 'location /b { return 200 "b"; }' >"${WL_ROOT}/beta/routes/alpha.example.test.conf"
edge_gather_workload_routes "${WL_ROOT}"
[[ -f "${ROUTES_DIR}/alpha--alpha.example.test.conf" ]] \
  || fail "gather must fulfill alpha's Intent-run Route"
[[ -f "${ROUTES_DIR}/beta--alpha.example.test.conf" ]] \
  || fail "gather must fulfill beta's Intent-run Route"
grep -Fq 'location /a' "${ROUTES_DIR}/alpha--alpha.example.test.conf" \
  || fail "alpha fulfilled Route must keep SoT bytes"
grep -Fq 'location /b' "${ROUTES_DIR}/beta--alpha.example.test.conf" \
  || fail "beta fulfilled Route must keep SoT bytes"
pass "gather-all fulfills Intent-run Route Declarations across Workloads"

# --- gather Intent filter: stop and trash drop fulfillment ---
printf '%s\n' '{"intent":"stop"}' >"${WL_ROOT}/alpha/manifest.json"
printf '%s\n' '{"intent":"trash"}' >"${WL_ROOT}/beta/manifest.json"
edge_gather_workload_routes "${WL_ROOT}"
[[ ! -f "${ROUTES_DIR}/alpha--alpha.example.test.conf" ]] \
  || fail "gather must drop fulfillment for Intent stop"
[[ ! -f "${ROUTES_DIR}/beta--alpha.example.test.conf" ]] \
  || fail "gather must drop fulfillment for Intent trash"
pass "gather drops fulfillment for Intent stop and trash"

# --- gather restores run and removes orphan Edge installs (SoT gone) ---
printf '%s\n' '{"intent":"run"}' >"${WL_ROOT}/alpha/manifest.json"
rm -rf "${WL_ROOT}/beta"
printf '%s\n' '# orphan' >"${ROUTES_DIR}/gone--alpha.example.test.conf"
printf '%s\n' '# legacy projected' >"${ROUTES_DIR}/alpha.conf"
printf '%s\n' '# legacy projected gone' >"${ROUTES_DIR}/gone.conf"
edge_gather_workload_routes "${WL_ROOT}"
[[ -f "${ROUTES_DIR}/alpha--alpha.example.test.conf" ]] \
  || fail "gather must fulfill remaining Intent-run Workload"
[[ ! -f "${ROUTES_DIR}/gone--alpha.example.test.conf" ]] \
  || fail "gather must remove fulfilled Routes when Workload SoT is gone"
[[ ! -f "${ROUTES_DIR}/beta--alpha.example.test.conf" ]] \
  || fail "gather must not leave Routes for removed Workload SoT"
[[ ! -f "${ROUTES_DIR}/alpha.conf" ]] \
  || fail "gather must one-shot delete leftover projected <wl>.conf"
[[ ! -f "${ROUTES_DIR}/gone.conf" ]] \
  || fail "gather must one-shot delete leftover projected <wl>.conf for gone Workloads"
pass "gather removes orphan Edge installs when Workload SoT is gone"

# --- gather fail-closed preserves prior good fulfillments ---
mkdir -p "${WL_ROOT}/beta/routes"
printf '%s\n' '{"intent":"run"}' >"${WL_ROOT}/beta/manifest.json"
printf '%s\n' 'location /b { return 200 "b"; }' >"${WL_ROOT}/beta/routes/alpha.example.test.conf"
edge_gather_workload_routes "${WL_ROOT}"
[[ -f "${ROUTES_DIR}/alpha--alpha.example.test.conf" ]] \
  || fail "precondition: alpha fulfilled before fail-closed gather"
[[ -f "${ROUTES_DIR}/beta--alpha.example.test.conf" ]] \
  || fail "precondition: beta fulfilled before fail-closed gather"
printf '%s\n' 'location /bad { return 200 "bad"; }' >"${WL_ROOT}/alpha/routes/off.example.test.conf"
if edge_gather_workload_routes "${WL_ROOT}" 2>/dev/null; then
  fail "expected gather fail-closed when a Route basename is not on the want-list"
fi
[[ -f "${ROUTES_DIR}/alpha--alpha.example.test.conf" ]] \
  || fail "gather fail-closed must leave prior good alpha fulfillment"
[[ ! -f "${ROUTES_DIR}/alpha--off.example.test.conf" ]] \
  || fail "gather fail-closed must not install off-want-list Route"
[[ -f "${ROUTES_DIR}/beta--alpha.example.test.conf" ]] \
  || fail "gather fail-closed must leave other Workloads' fulfillments"
pass "gather fail-closed preserves prior good fulfillments"

# --- gather noop when inputs and interior already match ---
rm -f "${WL_ROOT}/alpha/routes/off.example.test.conf"
edge_gather_workload_routes "${WL_ROOT}"
[[ -f "${ROUTES_DIR}/alpha--alpha.example.test.conf" ]] \
  || fail "precondition: alpha fulfilled after clearing off-want-list SoT"
[[ -f "${ROUTES_DIR}/beta--alpha.example.test.conf" ]] \
  || fail "precondition: beta fulfilled after clearing off-want-list SoT"
EDGE_ROUTES_CHANGED=1
edge_gather_workload_routes "${WL_ROOT}"
[[ "${EDGE_ROUTES_CHANGED}" == "0" ]] \
  || fail "unchanged gather inputs must set EDGE_ROUTES_CHANGED=0 (noop)"
pass "gather is a noop when inputs are unchanged"

echo "All Edge Route helper checks passed."
