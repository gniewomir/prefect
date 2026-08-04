#!/usr/bin/env bash
# Seam: Lifecycle Teardown-before-each call shape (ADR-0042 / #166) —
# observable: N cases ⇒ N Teardown baselines (stub teardown.sh; no cloud).
set -euo pipefail

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=baseline.sh
source "${CASE_DIR}/baseline.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

umask 077
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lifecycle-before-each.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

export REPO_ROOT="${TMP}"
export PLATFORM_ENV="test"
mkdir -p "${TMP}/environments/test"
RECORD="${TMP}/teardown.count"
cat >"${TMP}/teardown.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '1\n' >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${TMP}/teardown.args"
read -r _ || true
exit 0
EOF
chmod +x "${TMP}/teardown.sh"

: >"${RECORD}"
for label in a.sh b.sh c.sh; do
  lifecycle_baseline_stack_absent || fail "baseline failed before ${label}"
done
count="$(wc -l <"${RECORD}" | tr -d ' ')"
[[ "${count}" == "3" ]] || fail "Teardown baseline must run once per case (got ${count})"
grep -Fq 'args=--env test' "${TMP}/teardown.args" \
  || fail "each Teardown must receive --env test"
pass "Teardown baseline invoked once per case in a three-case loop"

# Wrong suite confirm still aborts (suite start; complements ./test.sh soft path).
if ( printf 'teardown please\n' | lifecycle_confirm_suite_teardown >/dev/null 2>&1 ); then
  fail "non-exact teardown confirm must abort"
fi
pass "suite teardown confirm rejects non-exact phrase"

echo "All lifecycle before-each checks passed."
