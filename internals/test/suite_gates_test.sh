#!/usr/bin/env bash
# Seam: ADR-0042 suite gates via ./test.sh (issue #166 / #159) —
# observable abort behavior, not Terraform internals.
# Lifecycle non-test --env fail-closed needs no Host credentials.
# Acceptance diagnose / Lifecycle teardown confirms reuse helper coverage in
# acceptance/baseline_test.sh and lifecycle/lib/baseline_test.sh; here we
# exercise the dispatcher → runner path where it aborts before Host work.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_SH="${REPO_ROOT}/test.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -x "${TEST_SH}" ]] || fail "missing executable ${TEST_SH}"

run_test_sh() {
  set +e
  OUT="$(printf '%s\n' "${STDIN_LINES-}" | "${TEST_SH}" "$@" 2>&1)"
  STATUS=$?
  set -e
}

# --- Lifecycle: non-test --env fail closed (before workspace / credentials) ---
STDIN_LINES=""
run_test_sh lifecycle --env prod
[[ "${STATUS}" -ne 0 ]] || fail "lifecycle --env prod: expected non-zero"
[[ "${OUT}" == *"test-Environment only"* ]] \
  || fail "lifecycle --env prod: expected fail-closed message, got: ${OUT}"
pass "lifecycle --env prod aborts (test-only)"

run_test_sh lifecycle --env example
[[ "${STATUS}" -ne 0 ]] || fail "lifecycle --env example: expected non-zero"
[[ "${OUT}" == *"test-Environment only"* ]] \
  || fail "lifecycle --env example: expected fail-closed message, got: ${OUT}"
pass "lifecycle --env example aborts (test-only)"

# --- Acceptance: non-test diagnose gate via runner (aborts before credentials) ---
STDIN_LINES="nope"
run_test_sh acceptance --env prod
[[ "${STATUS}" -ne 0 ]] || fail "acceptance --env prod without diagnose: expected non-zero"
[[ "${OUT}" == *"aborted (expected exact 'diagnose prod')"* ]] \
  || fail "acceptance without diagnose: expected abort, got: ${OUT}"
pass "acceptance --env prod without diagnose aborts"

STDIN_LINES="diagnose test"
run_test_sh acceptance --env prod
[[ "${STATUS}" -ne 0 ]] || fail "acceptance wrong diagnose slug: expected non-zero"
[[ "${OUT}" == *"aborted (expected exact 'diagnose prod')"* ]] \
  || fail "acceptance wrong slug: expected abort, got: ${OUT}"
pass "acceptance --env prod with wrong diagnose slug aborts"

# --- Lifecycle: wrong suite confirm aborts when the runner reaches the prompt ---
# Requires provider credential + operator configuration (same as a real Lifecycle start).
# Soft-skip when the suite stops earlier so Unit Tests stay Host-free by default.
STDIN_LINES="yes"
run_test_sh lifecycle
if [[ "${OUT}" == *"aborted (expected exact 'teardown')"* ]]; then
  [[ "${STATUS}" -ne 0 ]] || fail "lifecycle wrong teardown confirm: expected non-zero"
  pass "lifecycle without exact teardown aborts when prompted"
elif [[ "${OUT}" == *"Provider Credential"* || "${OUT}" == *"credential"* \
  || "${OUT}" == *"Operator Configuration"* || "${OUT}" == *"PROPRAETOR_"* ]]; then
  pass "lifecycle teardown-confirm gate skipped (no operator credentials in Unit seam)"
else
  fail "lifecycle wrong confirm: unexpected early failure: ${OUT}"
fi

echo "All suite gate checks passed."
