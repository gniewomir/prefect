#!/usr/bin/env bash
# Unit tests: Workload Route reconcile + want-list fail-closed (ADR-0028).
# No cloud Apply — temp dirs only.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=edge-routes-host.sh
source "${REPO_ROOT}/prefect/lib/edge-routes-host.sh"

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

echo "All Edge Route helper checks passed."
