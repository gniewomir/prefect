#!/usr/bin/env bash
# Mapping/alias checks for Environment resolution (ADR-0019 / #40).
# No cloud Apply — pure helper seam.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=environment.sh
source "${REPO_ROOT}/lib/environment.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

assert_workspace() {
  local input="$1"
  local want="$2"
  local got
  got="$(environment_workspace_for "${input}")" || fail "environment_workspace_for '${input}' exited non-zero"
  [[ "${got}" == "${want}" ]] || fail "input='${input}': want workspace '${want}', got '${got}'"
  pass "input='${input}' → workspace ${want}"
}

assert_workspace_fails() {
  local input="$1"
  local label="$2"
  if environment_workspace_for "${input}" >/dev/null 2>&1; then
    fail "expected failure for ${label} (input='${input}')"
  fi
  pass "rejects ${label}"
}

assert_workspace "" "default"
assert_workspace "default" "default"
assert_workspace "test" "default"
assert_workspace "prod" "prod"
assert_workspace "dev" "dev"
assert_workspace "staging" "staging"

assert_eq() {
  local got="$1"
  local want="$2"
  local label="$3"
  [[ "${got}" == "${want}" ]] || fail "${label}: want '${want}', got '${got}'"
  pass "${label}"
}

assert_eq "$(environment_slug_for "")" "test" "slug: empty → test"
assert_eq "$(environment_slug_for default)" "test" "slug: default → test"
assert_eq "$(environment_slug_for test)" "test" "slug: test → test"
assert_eq "$(environment_slug_for prod)" "prod" "slug: prod → prod"
assert_eq "$(environment_volume_name_for "")" "prefect-test-web-data" "volume: empty → prefect-test-web-data"
assert_eq "$(environment_volume_name_for prod)" "prefect-prod-web-data" "volume: prod → prefect-prod-web-data"

assert_workspace_fails " " "whitespace-only slug"
assert_workspace_fails "Test" "mixed-case slug (not aliased)"
assert_workspace_fails "default " "trailing whitespace"
assert_workspace_fails "../evil" "path-like slug"
assert_workspace_fails "has space" "slug with space"

parse_ok() {
  environment_parse_args "$@" || fail "parse failed for: $*"
  printf '%s\t%s\n' "${ENVIRONMENT_RAW}" "${ENVIRONMENT_REST[*]-}"
}

got="$(parse_ok --yes)"
[[ "${got}" == $'\t'--yes ]] || fail "no --env should leave env empty and keep --yes; got '${got}'"
pass "parse: --yes alone leaves env empty"

got="$(parse_ok --env test --yes)"
[[ "${got}" == $'test\t--yes' ]] || fail "want test + --yes; got '${got}'"
pass "parse: --env test --yes"

got="$(parse_ok --yes --env=prod)"
[[ "${got}" == $'prod\t--yes' ]] || fail "want prod + --yes; got '${got}'"
pass "parse: --yes --env=prod"

if environment_parse_args --env 2>/dev/null; then
  fail "expected failure for --env without value"
fi
pass "parse: rejects --env without value"

if environment_parse_args --env test --env prod 2>/dev/null; then
  fail "expected failure for duplicate --env"
fi
pass "parse: rejects duplicate --env"

echo "All Environment helper checks passed."
