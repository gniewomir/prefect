#!/usr/bin/env bash
# Fail if Stack .tf files introduce provider name = "…" literals outside naming.tf (ADR-0019 / #39).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${STACK_DIR}/naming.tf" ]] || fail "missing ${STACK_DIR}/naming.tf"

hits="$(
  grep -RInE --include='*.tf' '^\s*name\s*=\s*"' "${STACK_DIR}" \
    | grep -v '/naming\.tf:' \
    || true
)"

if [[ -n "${hits}" ]]; then
  echo "FAIL: provider name literals must come from local.names in naming.tf:" >&2
  echo "${hits}" >&2
  exit 1
fi

pass "no provider name literals outside terraform/naming.tf"
