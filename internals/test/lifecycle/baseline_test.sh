#!/usr/bin/env bash
# Seam: Lifecycle suite baseline helpers (ADR-0042 / #161) —
# test-only Environment gate, suite teardown confirm, Teardown-before-each.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=baseline.sh
source "${CASE_DIR}/baseline.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# --- test Environment only ---
PLATFORM_ENV="test"
lifecycle_require_test_environment || fail "test must be allowed"
pass "PLATFORM_ENV=test allowed"

# --env default is allowed at the CLI: environment_activate maps it to PLATFORM_ENV=test.
PLATFORM_ENV="prod"
if ( lifecycle_require_test_environment >/dev/null 2>&1 ); then
  fail "PLATFORM_ENV=prod must fail closed"
fi
pass "PLATFORM_ENV=prod rejected"

PLATFORM_ENV="example"
if ( lifecycle_require_test_environment >/dev/null 2>&1 ); then
  fail "PLATFORM_ENV=example must fail closed"
fi
pass "PLATFORM_ENV=example rejected"

# --- suite confirm: exact teardown ---
printf 'teardown\n' | lifecycle_confirm_suite_teardown >/dev/null \
  || fail "exact teardown must pass"
pass "exact teardown confirm accepted"

if ( printf 'yes\n' | lifecycle_confirm_suite_teardown >/dev/null 2>&1 ); then
  fail "wrong confirm phrase must abort"
fi
pass "wrong confirm phrase aborts"

if ( printf '\n' | lifecycle_confirm_suite_teardown >/dev/null 2>&1 ); then
  fail "empty confirm must abort"
fi
pass "empty confirm aborts"

# --- baseline absent: existing teardown.sh with confirm piped ---
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lifecycle-baseline.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
RECORD="${TMP}/teardown.record"
cat >"${TMP}/teardown.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'teardown\n' >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${RECORD}"
# Consume confirm line the way real teardown.sh does when destroying.
read -r _ || true
exit 0
EOF
chmod +x "${TMP}/teardown.sh"

export REPO_ROOT="${TMP}"
export PLATFORM_ENV="test"
: >"${RECORD}"
lifecycle_baseline_stack_absent
grep -Fxq 'teardown' "${RECORD}" || fail "baseline must invoke teardown.sh"
grep -Fq 'args=--env test' "${RECORD}" \
  || fail "Teardown must receive --env \${PLATFORM_ENV}"
pass "baseline invokes teardown.sh --env PLATFORM_ENV"

echo "All lifecycle baseline helper checks passed."
