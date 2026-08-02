#!/usr/bin/env bash
# Unit Test: run_buffered_case quiet-on-pass / dump-on-fail.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=run-buffered-case.sh
source "${REPO_ROOT}/internals/test/run-buffered-case.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/run-buffered-case.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

PASS_CASE="${TMP}/pass.sh"
FAIL_CASE="${TMP}/fail.sh"
cat >"${PASS_CASE}" <<'EOF'
#!/usr/bin/env bash
echo "pass-noise-should-be-hidden"
exit 0
EOF
cat >"${FAIL_CASE}" <<'EOF'
#!/usr/bin/env bash
echo "fail-noise-must-appear"
exit 1
EOF
chmod +x "${PASS_CASE}" "${FAIL_CASE}"

out="$(TEST_VERBOSE=0 run_buffered_case "pass-label" "${PASS_CASE}" 2>&1)" || fail "pass case should return 0"
echo "${out}" | grep -Fq -- '--- pass-label ---' || fail "pass case missing header: ${out}"
echo "${out}" | grep -Fq -- 'pass-noise-should-be-hidden' && fail "pass case leaked buffered output: ${out}"
pass "quiet on pass (header only)"

set +e
out="$(TEST_VERBOSE=0 run_buffered_case "fail-label" "${FAIL_CASE}" 2>&1)"
rc=$?
set -e
[[ ${rc} -ne 0 ]] || fail "fail case should return non-zero"
echo "${out}" | grep -Fq -- '--- fail-label ---' || fail "fail case missing header: ${out}"
echo "${out}" | grep -Fq -- 'fail-noise-must-appear' || fail "fail case did not dump log: ${out}"
pass "dump log on fail"

# TEST_VERBOSE=1 streams live (noise visible even on pass).
out="$(TEST_VERBOSE=1 run_buffered_case "verbose-pass" "${PASS_CASE}" 2>&1)" \
  || fail "verbose pass case should return 0"
echo "${out}" | grep -Fq -- '--- verbose-pass ---' || fail "verbose pass missing header: ${out}"
echo "${out}" | grep -Fq -- 'pass-noise-should-be-hidden' \
  || fail "verbose pass should stream case output: ${out}"
pass "TEST_VERBOSE=1 streams on pass"
