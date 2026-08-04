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
umask 077
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

# --- non-test baseline: Environment tree must match HEAD (ADR-0042 / #176) ---
GIT_ROOT="${TMP}/git-repo"
mkdir -p "${GIT_ROOT}/internals" "${GIT_ROOT}/environments/prod"
cp "${TMP}/internals/ensure.sh" "${GIT_ROOT}/internals/ensure.sh"
git -C "${GIT_ROOT}" init -q
git -C "${GIT_ROOT}" config user.email "baseline@test"
git -C "${GIT_ROOT}" config user.name "Baseline Test"
printf '{}\n' >"${GIT_ROOT}/environments/prod/domains.json"
git -C "${GIT_ROOT}" add environments/prod/domains.json
git -C "${GIT_ROOT}" -c commit.gpgsign=false commit -q -m "prod SoT"

export REPO_ROOT="${GIT_ROOT}"
export PLATFORM_ENV="prod"
RECORD="${GIT_ROOT}/ensure.record"
: >"${RECORD}"
cat >"${GIT_ROOT}/internals/ensure.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ensure\n' >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${RECORD}"
exit 0
EOF
chmod +x "${GIT_ROOT}/internals/ensure.sh"

acceptance_baseline_deployed \
  || fail "clean Environment tree must allow non-test baseline Deploy"
grep -Fq 'args=--env prod' "${RECORD}" || fail "clean non-test baseline must still Deploy"
pass "non-test baseline Deploy allowed when Environment tree matches HEAD"

rm -rf "${GIT_ROOT}/environments/prod/untracked-fixture"
mkdir -p "${GIT_ROOT}/environments/prod/untracked-fixture"
printf 'dirty\n' >"${GIT_ROOT}/environments/prod/untracked-fixture/manifest.json"
: >"${RECORD}"
if ( acceptance_baseline_deployed >/dev/null 2>&1 ); then
  fail "dirty untracked Environment path must abort non-test baseline Deploy"
fi
[[ ! -s "${RECORD}" ]] || fail "dirty-tree abort must not invoke ensure.sh"
pass "non-test baseline aborts on untracked Environment path"

rm -rf "${GIT_ROOT}/environments/prod/untracked-fixture"
printf '{ "changed": true }\n' >"${GIT_ROOT}/environments/prod/domains.json"
: >"${RECORD}"
if ( acceptance_baseline_deployed >/dev/null 2>&1 ); then
  fail "modified tracked Environment path must abort non-test baseline Deploy"
fi
[[ ! -s "${RECORD}" ]] || fail "dirty tracked abort must not invoke ensure.sh"
pass "non-test baseline aborts on modified tracked Environment path"

git -C "${GIT_ROOT}" checkout HEAD -- environments/prod/domains.json
# gitignored Environment Configuration must not trip the gate
printf '*/.env\n' >"${GIT_ROOT}/environments/.gitignore"
printf 'SECRET=1\n' >"${GIT_ROOT}/environments/prod/.env"
: >"${RECORD}"
acceptance_baseline_deployed \
  || fail "gitignored Environment Configuration .env must not block non-test Deploy"
grep -Fq 'args=--env prod' "${RECORD}" || fail "Deploy must run when only .env is present"
pass "non-test baseline ignores Environment Configuration .env"

export PLATFORM_ENV="test"
mkdir -p "${GIT_ROOT}/environments/test/fixture-wl"
printf '{ "intent": "run" }\n' >"${GIT_ROOT}/environments/test/fixture-wl/manifest.json"
: >"${RECORD}"
acceptance_baseline_deployed \
  || fail "test Environment must allow dirty Environment tree for fixtures"
grep -Fq 'args=--env test' "${RECORD}" || fail "test baseline must Deploy despite dirty tree"
pass "test baseline skips Environment dirty-tree gate"

# --- fixture-class detection + diagnose filter (ADR-0042 / #176) ---
CASES_DIR="${TMP}/cases"
mkdir -p "${CASES_DIR}"
cat >"${CASES_DIR}/10-safe.sh" <<'EOF'
#!/usr/bin/env bash
echo safe
EOF
cat >"${CASES_DIR}/76-fixture.sh" <<'EOF'
#!/usr/bin/env bash
acceptance_wl_track "ephemeral"
EOF
cat >"${CASES_DIR}/90-sot.sh" <<'EOF'
#!/usr/bin/env bash
acceptance_sot_track "committed/manifest.json"
EOF

acceptance_case_is_fixture_class "${CASES_DIR}/10-safe.sh" \
  && fail "case without track helpers must not be fixture-class"
acceptance_case_is_fixture_class "${CASES_DIR}/76-fixture.sh" \
  || fail "acceptance_wl_track reference must mark fixture-class"
acceptance_case_is_fixture_class "${CASES_DIR}/90-sot.sh" \
  || fail "acceptance_sot_track reference must mark fixture-class"
pass "fixture-class derived from track helper references"

export PLATFORM_ENV="prod"
FILTERED=()
while IFS= read -r p; do
  [[ -n "${p}" ]] || continue
  FILTERED+=("${p}")
done < <(acceptance_filter_diagnose_cases "${CASES_DIR}/10-safe.sh" "${CASES_DIR}/76-fixture.sh" "${CASES_DIR}/90-sot.sh")
[[ ${#FILTERED[@]} -eq 1 ]] || fail "full diagnose filter must keep only non-fixture cases, got ${#FILTERED[@]}"
[[ "$(basename "${FILTERED[0]}")" == "10-safe.sh" ]] \
  || fail "full diagnose filter must keep 10-safe.sh"
pass "full-suite diagnose filter skips fixture-class cases"

if ( acceptance_refuse_if_diagnose_fixture_selector "${CASES_DIR}/76-fixture.sh" >/dev/null 2>&1 ); then
  fail "explicit fixture-class selector on non-test must refuse"
fi
pass "explicit fixture-class selector refuses on non-test"

acceptance_refuse_if_diagnose_fixture_selector "${CASES_DIR}/10-safe.sh" \
  || fail "explicit safe selector on non-test must be allowed"
pass "explicit safe selector allowed on non-test"

export PLATFORM_ENV="test"
FILTERED=()
while IFS= read -r p; do
  [[ -n "${p}" ]] || continue
  FILTERED+=("${p}")
done < <(acceptance_filter_diagnose_cases "${CASES_DIR}/10-safe.sh" "${CASES_DIR}/76-fixture.sh")
[[ ${#FILTERED[@]} -eq 2 ]] || fail "test Environment must not filter fixture-class cases"
pass "test Environment keeps fixture-class cases"

echo "All acceptance baseline helper checks passed."
