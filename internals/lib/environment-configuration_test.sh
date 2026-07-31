#!/usr/bin/env bash
# Offline tests: Environment Configuration bag resolve (ADR-0035).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=environment-configuration.sh
source "${REPO_ROOT}/internals/lib/environment-configuration.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/envcfg.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
MANIFEST="${TMP}/manifest.json"
ENV_DIR="${TMP}/env"
OUT="${TMP}/out.env"
mkdir -p "${ENV_DIR}"

cat >"${MANIFEST}" <<'EOF'
{ "intent": "run" }
EOF
eval "$(environment_configuration_resolve "${MANIFEST}" "${ENV_DIR}" "${OUT}")"
[[ "${WL_ENV_ACTIVE}" == "0" ]] || fail "omit environment should be inactive"
[[ ! -f "${OUT}" ]] || fail "omit should not write outfile"
pass "omit environment → inactive"

cat >"${MANIFEST}" <<'EOF'
{ "intent": "run", "environment": [] }
EOF
eval "$(environment_configuration_resolve "${MANIFEST}" "${ENV_DIR}" "${OUT}")"
[[ "${WL_ENV_ACTIVE}" == "0" ]] || fail "[] should be inactive"
pass "[] environment → inactive"

cat >"${MANIFEST}" <<'EOF'
{ "intent": "run", "environment": ["A", "B"] }
EOF
printf 'A=from-file\nB=file-b\nC=surplus\n' >"${ENV_DIR}/.env"
unset A B C || true
eval "$(environment_configuration_resolve "${MANIFEST}" "${ENV_DIR}" "${OUT}")"
[[ "${WL_ENV_ACTIVE}" == "1" ]] || fail "listed keys should be active"
grep -Fx 'A=from-file' "${OUT}" >/dev/null || fail "expected A from file"
grep -Fx 'B=file-b' "${OUT}" >/dev/null || fail "expected B from file"
grep -F 'surplus' "${OUT}" >/dev/null && fail "surplus must not appear"
pass ".env baseline lists only Manifest keys"

export A=from-shell
eval "$(environment_configuration_resolve "${MANIFEST}" "${ENV_DIR}" "${OUT}")"
grep -Fx 'A=from-shell' "${OUT}" >/dev/null || fail "shell should override file"
grep -Fx 'B=file-b' "${OUT}" >/dev/null || fail "B should remain from file"
pass "shell overrides .env"

unset A B || true
printf 'A=only\n' >"${ENV_DIR}/.env"
if environment_configuration_resolve "${MANIFEST}" "${ENV_DIR}" "${OUT}" >/dev/null 2>&1; then
  fail "missing B should fail closed"
fi
pass "missing listed key fails closed"

printf 'export A=nope\nB=x\n' >"${ENV_DIR}/.env"
if environment_configuration_resolve "${MANIFEST}" "${ENV_DIR}" "${OUT}" >/dev/null 2>&1; then
  fail "export line should fail closed"
fi
pass "invalid dotenv export fails closed"

TREE="${TMP}/wl"
mkdir -p "${TREE}"
if environment_configuration_require_containers "${TREE}" 1 >/dev/null 2>&1; then
  fail "active without .container should fail"
fi
mkdir -p "${TREE}/quadlets"
touch "${TREE}/quadlets/x.container"
environment_configuration_require_containers "${TREE}" 1 || fail "should accept .container"
environment_configuration_require_containers "${TREE}" 0 || fail "inactive should skip"
pass "require_containers gate"

echo "All environment-configuration offline tests passed."
