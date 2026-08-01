#!/usr/bin/env bash
# Seam: write_subtractive_domain_override (#63). No cloud access.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export REPO_ROOT="${TMP_DIR}/repo"
export PLATFORM_ENV=test

mkdir -p "${REPO_ROOT}/internals/lib" "${REPO_ROOT}/internals/test/acceptance" \
  "${REPO_ROOT}/environments/test"
cp "${REAL_ROOT}/internals/lib/environment.sh" "${REPO_ROOT}/internals/lib/environment.sh"
cat >"${REPO_ROOT}/internals/test/acceptance/lib.sh" <<'EOF'
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
configured_domain_names() { :; }
environment_domains_path() { :; }
EOF

printf '%s\n' '{
  "zebra.example": {"names": ["@"]},
  "alpha.example": {"names": ["@", "www"]}
}' >"${REPO_ROOT}/environments/test/domains.json"

# shellcheck source=lib.sh
source "${REAL_ROOT}/internals/test/lifecycle/lib.sh"

dropped="$(write_subtractive_domain_override)"
[[ "${dropped}" == "alpha.example" ]] \
  || fail "subtractive must drop lex-first apex, got '${dropped}'"
override="$(domains_override_path)"
[[ -f "${override}" ]] || fail "subtractive override missing"
jq -e 'has("alpha.example") | not' "${override}" >/dev/null \
  || fail "dropped apex must be absent from override"
jq -e '.["zebra.example"].names == ["@"]' "${override}" >/dev/null \
  || fail "remaining apex must be preserved in override"
pass "write_subtractive_domain_override drops lex-first apex only"

remove_domain_override
[[ ! -f "${override}" ]] || fail "remove_domain_override must delete the file"

echo "All subtractive Domain override helper checks passed."
