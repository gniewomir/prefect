#!/usr/bin/env bash
# Unit tests: Deploy ladder orchestrator (ensure.sh) and root deploy.sh (#158 / ADR-0041).
# Seams: entrypoint presence; ladder composition order; Deploy does not Apply.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

INTERNALS="${REPO_ROOT}/internals"
ENSURE="${INTERNALS}/ensure.sh"
DEPLOY="${REPO_ROOT}/deploy.sh"

[[ -f "${ENSURE}" ]] || fail "missing ${ENSURE}"
[[ -f "${DEPLOY}" ]] || fail "missing ${DEPLOY}"
[[ -x "${ENSURE}" ]] || fail "ensure.sh not executable"
[[ -x "${DEPLOY}" ]] || fail "deploy.sh not executable"
pass "ensure.sh and deploy.sh entrypoints exist"

# Ladder order must match ADR-0041 (Fabric → Mirror → Orphan Reap → Components → Workloads → Purge).
want_order=$'ensure-fabric.sh\nensure-mirror.sh\npurge-orphans.sh\nensure-components.sh\nensure-workloads.sh\npurge-trash.sh'
got_order="$(
  grep -oE 'internals/(ensure-fabric|ensure-mirror|purge-orphans|ensure-components|ensure-workloads|purge-trash)\.sh' "${ENSURE}" \
    | awk -F/ '{print $NF}'
)"
[[ "${got_order}" == "${want_order}" ]] || fail "ensure.sh ladder order want:
${want_order}
got:
${got_order}"
pass "ensure.sh composes Deploy ladder in ADR-0041 order"

grep -Eq 'apply\.sh|terraform[[:space:]]+apply' "${ENSURE}" \
  && fail "ensure.sh must not invoke Stack Apply" || true
pass "ensure.sh does not invoke Stack Apply"

# deploy.sh: wait IHP, invoke ensure.sh, never Apply.
grep -Fq 'ensure.sh' "${DEPLOY}" || fail "deploy.sh must invoke ensure.sh"
grep -Fq 'host_wait_until_ihp_done' "${DEPLOY}" || fail "deploy.sh must wait for IHP Done"
grep -Fq 'host_session_open' "${DEPLOY}" || fail "deploy.sh must open a Host session"
grep -Eq 'apply\.sh|terraform[[:space:]]+apply' "${DEPLOY}" \
  && fail "deploy.sh must not invoke Stack Apply" || true
pass "deploy.sh waits for IHP Done, runs ensure.sh, does not Apply"

# Acceptance bring-up uses ensure.sh (not legacy fabric+components-only).
RUNNER="${REPO_ROOT}/internals/test/acceptance/run.sh"
grep -Fq 'internals/ensure.sh' "${RUNNER}" || fail "Acceptance runner must invoke ensure.sh"
grep -Fq 'ensure-fabric.sh' "${RUNNER}" && fail "Acceptance runner must not call ensure-fabric directly" || true
grep -Fq 'ensure-components.sh' "${RUNNER}" && fail "Acceptance runner must not call ensure-components directly" || true
pass "Acceptance bring-up uses ensure.sh"

echo "All ensure/deploy ladder checks passed."
