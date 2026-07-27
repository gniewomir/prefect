#!/usr/bin/env bash
# Domain assignment → ACME want-list FQDNs (ADR-0023 / #55).
# No cloud Apply — pure helper seam.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=domains.sh
source "${REPO_ROOT}/lib/domains.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

assert_fqdns() {
  local slug="$1"
  shift
  local want=("$@")
  local got
  got="$(domains_acme_fqdns_for "${slug}")" || fail "domains_acme_fqdns_for '${slug}' exited non-zero"
  local -a got_lines=()
  if [[ -n "${got}" ]]; then
    while IFS= read -r line; do
      got_lines+=("${line}")
    done <<<"${got}"
  fi
  local i
  [[ "${#got_lines[@]}" -eq "${#want[@]}" ]] \
    || fail "slug='${slug}': want ${#want[@]} FQDNs (${want[*]}), got ${#got_lines[@]} (${got_lines[*]-})"
  for i in "${!want[@]}"; do
    [[ "${got_lines[$i]}" == "${want[$i]}" ]] \
      || fail "slug='${slug}' index ${i}: want '${want[$i]}', got '${got_lines[$i]}'"
  done
  pass "slug='${slug}' → ${want[*]:-(empty)}"
}

# Committed test Environment Domain assignment (independent expected literals).
assert_fqdns test \
  api.gniewomir.pl \
  gniewomir.pl \
  www.gniewomir.pl

# Missing domains.json → empty set.
TMP_ENV="$(mktemp -d)"
trap 'rm -rf "${TMP_ENV}"' EXIT
mkdir -p "${TMP_ENV}/config/environments/empty-env"
# Point helper at temp tree via REPO_ROOT override
REPO_ROOT="${TMP_ENV}"
assert_fqdns empty-env

echo "All domains ACME FQDN helper checks passed."
