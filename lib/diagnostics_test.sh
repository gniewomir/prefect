#!/usr/bin/env bash
# Host diagnostics arg/bundle seam (pure helper — no SSH).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=diagnostics.sh
source "${REPO_ROOT}/lib/diagnostics.sh"

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
assert_eq "$(diagnostics_bundle_or_default "")" "ihp" "bundle: empty → ihp"
assert_eq "$(diagnostics_bundle_or_default ihp)" "ihp" "bundle: ihp → ihp"

if diagnostics_bundle_or_default cloud-init >/dev/null 2>&1; then
  fail "expected failure for unknown bundle cloud-init"
fi
pass "bundle: rejects unknown id"

# --- ihp artifact set ---
assert_eq "$(diagnostics_bundle_log_files ihp | tr '\n' ' ')" \
  "/var/log/cloud-init-output.log /var/log/cloud-init.log " \
  "ihp log files"
assert_eq "$(diagnostics_bundle_status_snapshot ihp)" \
  "cloud-init-status-long.txt" \
  "ihp status snapshot name"

# --- parse args ---
parse_ok() {
  diagnostics_parse_args "$@" || fail "parse failed for: $*"
  printf '%s\t%s\n' "${DIAGNOSTICS_BUNDLE_RAW}" "${DIAGNOSTICS_OUT}"
}

got="$(parse_ok)"
[[ "${got}" == $'\t' ]] || fail "no flags should leave bundle and out empty; got '${got}'"
pass "parse: no flags"

got="$(parse_ok --bundle=ihp)"
[[ "${got}" == $'ihp\t' ]] || fail "want ihp + empty out; got '${got}'"
pass "parse: --bundle=ihp"

got="$(parse_ok --bundle ihp --out /tmp/diag-out)"
[[ "${got}" == $'ihp\t/tmp/diag-out' ]] || fail "want ihp + /tmp/diag-out; got '${got}'"
pass "parse: --bundle ihp --out /tmp/diag-out"

got="$(parse_ok --out=/tmp/x)"
[[ "${got}" == $'\t/tmp/x' ]] || fail "want empty bundle + /tmp/x; got '${got}'"
pass "parse: --out=/tmp/x"

if diagnostics_parse_args --bundle 2>/dev/null; then
  fail "expected failure for --bundle without value"
fi
pass "parse: rejects --bundle without value"

if diagnostics_parse_args --out 2>/dev/null; then
  fail "expected failure for --out without value"
fi
pass "parse: rejects --out without value"

if diagnostics_parse_args --bundle=ihp --bundle=ihp 2>/dev/null; then
  fail "expected failure for duplicate --bundle"
fi
pass "parse: rejects duplicate --bundle"

if diagnostics_parse_args --out=/a --out=/b 2>/dev/null; then
  fail "expected failure for duplicate --out"
fi
pass "parse: rejects duplicate --out"

if diagnostics_parse_args --paths=/var/log/x 2>/dev/null; then
  fail "expected failure for unknown flag"
fi
pass "parse: rejects unknown flag"

echo "All Host diagnostics helper checks passed."
