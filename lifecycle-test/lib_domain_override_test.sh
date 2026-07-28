#!/usr/bin/env bash
# Seam: write_subtractive_domain_override / write_additive_domain_override (#62/#63).
# No cloud access.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export REPO_ROOT="${TMP_DIR}/repo"
export PREFECT_ENV=test

mkdir -p "${REPO_ROOT}/lib" "${REPO_ROOT}/test" \
  "${REPO_ROOT}/config/environments/test"
cp "${REAL_ROOT}/lib/environment.sh" "${REPO_ROOT}/lib/environment.sh"
cat >"${REPO_ROOT}/test/lib.sh" <<'EOF'
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
configured_domain_names() { :; }
environment_domains_path() { :; }
EOF

printf '%s\n' '{
  "zebra.example": {"names": ["@"]},
  "alpha.example": {"names": ["@", "www"]}
}' >"${REPO_ROOT}/config/environments/test/domains.json"

# shellcheck source=lib.sh
source "${REAL_ROOT}/lifecycle-test/lib.sh"

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

fixture="$(write_additive_domain_override)"
[[ "${fixture}" == "lifecycle-test.alpha.example" ]] \
  || fail "additive fixture apex unexpected: '${fixture}'"
jq -e --arg f "${fixture}" 'has($f) and .[$f].names == ["@"]' "$(domains_override_path)" >/dev/null \
  || fail "additive override must include fixture apex"
jq -e 'has("alpha.example") and has("zebra.example")' "$(domains_override_path)" >/dev/null \
  || fail "additive override must retain committed apexes"
pass "write_additive_domain_override keeps committed map and adds fixture"

remove_domain_override
echo "All Domain override helper checks passed."
