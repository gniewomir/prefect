#!/usr/bin/env bash
# Fail if Stack Domain config path no longer resolves to repo-root config/ (ADR-0021 / ADR-0032).
# Regression: after moving the Stack under internals/, ../config pointed at a missing tree and
# Domains loaded as {} — Cloud Project membership dropped Domain URNs on Apply.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
DOMAIN_TF="${STACK_DIR}/domain.tf"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${DOMAIN_TF}" ]] || fail "missing ${DOMAIN_TF}"

# Contract: Domain assignment files live at <repo>/config/environments/<slug>/…
# relative to the Stack root (internals/terraform/), that is ../../config/environments.
if ! grep -Eq 'domains_dir\s*=\s*"\$\{path\.(root|module)\}/\.\./\.\./config/environments/' "${DOMAIN_TF}"; then
  fail "domain.tf domains_dir must use ../../config/environments from the Stack root (repo-root config/)"
fi

resolved="$(cd "${STACK_DIR}/../../config/environments" && pwd)"
expected="$(cd "${REPO_ROOT}/config/environments" && pwd)"
[[ "${resolved}" == "${expected}" ]] \
  || fail "Stack ../../config/environments resolves to ${resolved}, expected ${expected}"

pass "Domain config path resolves to repository config/environments"
