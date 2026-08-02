#!/usr/bin/env bash
# Host diagnostics bundle seam (pure helper — no SSH). Argv grammar: cli_test.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=diagnostics.sh
source "${REPO_ROOT}/internals/lib/diagnostics.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

assert_eq() {
  local got="$1"
  local want="$2"
  local label="$3"
  [[ "${got}" == "${want}" ]] || fail "${label}: want '${want}', got '${got}'"
  pass "${label}"
}

# --- resolve bundle ---
if diagnostics_resolve_bundle "" >/dev/null 2>&1; then
  fail "expected failure for empty bundle id"
fi
pass "bundle: rejects empty id"

assert_eq "$(diagnostics_resolve_bundle ihp)" "ihp" "bundle: ihp → ihp"

if diagnostics_resolve_bundle cloud-init >/dev/null 2>&1; then
  fail "expected failure for unknown bundle cloud-init"
fi
pass "bundle: rejects unknown id"

assert_eq "$(diagnostics_known_bundles)" "ihp" "known bundles list"

# --- usage mentions required --bundle ---
usage="$(diagnostics_usage 2>&1)"
printf '%s' "${usage}" | grep -q -- '--bundle <id>' || fail "usage missing --bundle <id>"
printf '%s' "${usage}" | grep -q 'Required' || fail "usage should mark --bundle required"
printf '%s' "${usage}" | grep -q '^  ihp' || fail "usage missing ihp bundle line"
pass "usage: required --bundle and ihp listed"

# --- ihp artifact set ---
assert_eq "$(diagnostics_bundle_log_files ihp | tr '\n' ' ')" \
  "/var/log/cloud-init-output.log /var/log/cloud-init.log " \
  "ihp log files"
assert_eq "$(diagnostics_bundle_status_snapshot ihp)" \
  "cloud-init-status-long.txt" \
  "ihp status snapshot name"

echo "All Host diagnostics helper checks passed."
