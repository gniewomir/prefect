#!/usr/bin/env bash
# Domain assignment path resolution (ADR-0021 override priority).
# No cloud Apply — pure helper seam.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=domains.sh
source "${REPO_ROOT}/internals/lib/domains/domains.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP_ENV="$(mktemp -d)"
trap 'rm -rf "${TMP_ENV}"' EXIT
export REPO_ROOT="${TMP_ENV}"

mkdir -p "${TMP_ENV}/environments/alpha"

# Neither file → empty stdout.
got="$(domains_assignment_path alpha)" || fail "domains_assignment_path exited non-zero with no files"
[[ -z "${got}" ]] || fail "want empty path with no files, got '${got}'"
pass "neither file → empty"

# Only domains.json → that path.
printf '%s\n' '{"example.com":{"names":["@"]}}' \
  >"${TMP_ENV}/environments/alpha/domains.json"
got="$(domains_assignment_path alpha)" || fail "domains_assignment_path exited non-zero with domains.json"
[[ "${got}" == "${TMP_ENV}/environments/alpha/domains.json" ]] \
  || fail "want committed domains.json, got '${got}'"
pass "only domains.json → committed path"

# Override present → override replaces committed.
printf '%s\n' '{"lifecycle-test.example.com":{"names":["@"]}}' \
  >"${TMP_ENV}/environments/alpha/domains.override.json"
got="$(domains_assignment_path alpha)" || fail "domains_assignment_path exited non-zero with override"
[[ "${got}" == "${TMP_ENV}/environments/alpha/domains.override.json" ]] \
  || fail "want override path, got '${got}'"
pass "override present → override path (replace)"

# Missing slug arg → fail.
if domains_assignment_path >/dev/null 2>&1; then
  fail "domains_assignment_path with no slug should fail"
fi
pass "missing slug → non-zero"

echo "All Domain assignment path checks passed."
