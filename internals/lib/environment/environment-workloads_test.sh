#!/usr/bin/env bash
# Unit tests: Environment Workload discovery by manifest.json presence (ADR-0041 / #156).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=environment-workloads.sh
source "${REPO_ROOT}/internals/lib/environment/environment-workloads.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/env-workloads.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
ENV_DIR="${TMP}/env"
mkdir -p "${ENV_DIR}"

# Empty Environment → no Workloads
got="$(environment_discover_workloads "${ENV_DIR}")"
[[ -z "${got}" ]] || fail "empty env should discover nothing, got: ${got}"
pass "empty Environment discovers no Workloads"

# Non-Workload files and dirs without Manifest are ignored
printf '{}\n' >"${ENV_DIR}/domains.json"
printf 'X=1\n' >"${ENV_DIR}/.env"
mkdir -p "${ENV_DIR}/.hidden" "${ENV_DIR}/no-manifest"
printf '{"intent":"run"}\n' >"${ENV_DIR}/.hidden/manifest.json"
printf 'note\n' >"${ENV_DIR}/no-manifest/README.md"
got="$(environment_discover_workloads "${ENV_DIR}")"
[[ -z "${got}" ]] || fail "non-Workload entries should be ignored, got: ${got}"
pass "domains.json, .env, hidden, and non-Manifest dirs are ignored"

# Discover by manifest.json presence; sort stable; do not validate Manifest content
mkdir -p "${ENV_DIR}/zeta" "${ENV_DIR}/alpha" "${ENV_DIR}/beta"
printf 'not-json\n' >"${ENV_DIR}/zeta/manifest.json"
printf '{"intent":"run"}\n' >"${ENV_DIR}/alpha/manifest.json"
printf '{"intent":"trash"}\n' >"${ENV_DIR}/beta/manifest.json"
# Nested tree must not be discovered (immediate children only)
mkdir -p "${ENV_DIR}/alpha/nested"
printf '{"intent":"run"}\n' >"${ENV_DIR}/alpha/nested/manifest.json"

got="$(environment_discover_workloads "${ENV_DIR}" | paste -sd, -)"
[[ "${got}" == "alpha,beta,zeta" ]] || fail "want alpha,beta,zeta got '${got}'"
pass "discovers immediate Manifest dirs sorted; ignores nested and invalid JSON content"

echo "All environment-workloads discovery checks passed."
