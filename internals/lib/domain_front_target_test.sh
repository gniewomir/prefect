#!/usr/bin/env bash
# Domain-front Acceptance FQDN selection (#79).
# Pure helper seam — no dig, no cloud.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=domain_front_target.sh
source "${REPO_ROOT}/internals/lib/domain_front_target.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

ANSWERS="$(mktemp "${TMPDIR:-/tmp}/prefect-df-answers.XXXXXX")"
trap 'rm -f "${ANSWERS}"' EXIT

assert_select() {
  local reserved_ip="$1"
  local want_fqdn="$2"
  local want_ready="$3"
  shift 3
  local got
  got="$(printf '%s\n' "$@" | domain_front_select_target "${reserved_ip}" "${ANSWERS}")" \
    || fail "domain_front_select_target exited non-zero"
  local got_fqdn got_ready
  got_fqdn="$(printf '%s\n' "${got}" | awk '{print $1}')"
  got_ready="$(printf '%s\n' "${got}" | awk '{print $2}')"
  [[ "${got_fqdn}" == "${want_fqdn}" ]] \
    || fail "FQDN: want '${want_fqdn}', got '${got_fqdn}' (full='${got}')"
  [[ "${got_ready}" == "${want_ready}" ]] \
    || fail "ready: want '${want_ready}', got '${got_ready}' (full='${got}')"
  pass "→ ${want_fqdn} ${want_ready}"
}

# Empty want-list → empty stdout.
: >"${ANSWERS}"
got="$(printf '' | domain_front_select_target 203.0.113.10 "${ANSWERS}" || true)"
[[ -z "${got}" ]] || fail "empty want-list should print nothing, got '${got}'"
pass "empty want-list → empty"

# Prefer lex-first DNS-ready at Reserved IP over earlier lex name that is not ready.
cat >"${ANSWERS}" <<'EOF'
alpha.example 198.51.100.1
beta.example 203.0.113.10
gamma.example 203.0.113.10
EOF
assert_select 203.0.113.10 beta.example ready \
  gamma.example beta.example alpha.example

# No DNS-ready → lex-first want-list name, not-ready.
cat >"${ANSWERS}" <<'EOF'
alpha.example 198.51.100.1
beta.example 198.51.100.2
EOF
assert_select 203.0.113.10 alpha.example not-ready \
  beta.example alpha.example

# Single want-list name DNS-ready.
cat >"${ANSWERS}" <<'EOF'
solo.example 203.0.113.10
EOF
assert_select 203.0.113.10 solo.example ready solo.example

echo "All domain_front_select_target checks passed."
