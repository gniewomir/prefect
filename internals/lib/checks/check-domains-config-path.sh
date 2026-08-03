#!/usr/bin/env bash
# Fail if Stack Domain config path no longer resolves to repo-root environments/ (ADR-0021 / ADR-0033).
# Regression: after moving the Stack under internals/, a wrong relative path loaded Domains as {} —
# Cloud Project membership dropped Domain URNs on Apply.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
DOMAIN_TF="${STACK_DIR}/domain.tf"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${DOMAIN_TF}" ]] || fail "missing ${DOMAIN_TF}"

# Contract: Domain assignment files live at <repo>/environments/<slug>/…
# relative to the Stack root (internals/terraform/), that is ../../environments.
if ! grep -Eq 'domains_dir\s*=\s*"\$\{path\.(root|module)\}/\.\./\.\./environments/' "${DOMAIN_TF}"; then
  fail "domain.tf domains_dir must use ../../environments from the Stack root (repo-root environments/)"
fi

resolved="$(cd "${STACK_DIR}/../../environments" && pwd)"
expected="$(cd "${REPO_ROOT}/environments" && pwd)"
[[ "${resolved}" == "${expected}" ]] \
  || fail "Stack ../../environments resolves to ${resolved}, expected ${expected}"

pass "Domain config path resolves to repository environments/"
