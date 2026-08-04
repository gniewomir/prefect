#!/usr/bin/env bash
# Seam: Acceptance suite baseline helpers (ADR-0042 / #162) —
# diagnose gate for non-test Environments; Deploy-before-each via ensure.sh.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=baseline.sh
source "${CASE_DIR}/baseline.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# --- diagnose: test / default alias skips confirm ---
PLATFORM_ENV="test"
acceptance_confirm_diagnose >/dev/null \
  || fail "PLATFORM_ENV=test must skip diagnose confirm"
pass "PLATFORM_ENV=test skips diagnose confirm"

# --- diagnose: non-test requires exact 'diagnose <slug>' matching PLATFORM_ENV ---
PLATFORM_ENV="prod"
printf 'diagnose prod\n' | acceptance_confirm_diagnose >/dev/null \
  || fail "exact diagnose prod must pass"
pass "exact diagnose prod accepted"

PLATFORM_ENV="prod"
if ( printf 'diagnose test\n' | acceptance_confirm_diagnose >/dev/null 2>&1 ); then
  fail "diagnose with wrong slug must abort"
fi
pass "wrong diagnose slug aborts"

PLATFORM_ENV="prod"
if ( printf 'yes\n' | acceptance_confirm_diagnose >/dev/null 2>&1 ); then
  fail "wrong confirm phrase must abort"
fi
pass "wrong confirm phrase aborts"

PLATFORM_ENV="prod"
if ( printf '\n' | acceptance_confirm_diagnose >/dev/null 2>&1 ); then
  fail "empty confirm must abort"
fi
pass "empty confirm aborts"

PLATFORM_ENV="staging"
printf 'diagnose staging\n' | acceptance_confirm_diagnose >/dev/null \
  || fail "exact diagnose staging must pass for PLATFORM_ENV=staging"
pass "diagnose slug must match active PLATFORM_ENV"

# --- baseline Deployed: existing ensure.sh path ---
TMP="$(mktemp -d "${TMPDIR:-/tmp}/acceptance-baseline.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
RECORD="${TMP}/ensure.record"
mkdir -p "${TMP}/internals"
cat >"${TMP}/internals/ensure.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ensure\n' >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${RECORD}"
exit 0
EOF
chmod +x "${TMP}/internals/ensure.sh"

export REPO_ROOT="${TMP}"
export PLATFORM_ENV="test"
: >"${RECORD}"
acceptance_baseline_deployed
grep -Fxq 'ensure' "${RECORD}" || fail "baseline must invoke internals/ensure.sh"
grep -Fq 'args=--env test' "${RECORD}" \
  || fail "Deploy must receive --env \${PLATFORM_ENV}"
pass "baseline invokes internals/ensure.sh --env PLATFORM_ENV"

export PLATFORM_ENV="prod"
: >"${RECORD}"
acceptance_baseline_deployed
grep -Fq 'args=--env prod' "${RECORD}" \
  || fail "non-test baseline must still Deploy with --env PLATFORM_ENV"
pass "non-test baseline still Deploys via ensure.sh"

echo "All acceptance baseline helper checks passed."
