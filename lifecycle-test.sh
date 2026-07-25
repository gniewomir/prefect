#!/usr/bin/env bash
# Lifecycle Test runner — Park / Apply-after-Park / Teardown (destructive; opt-in).
# Not Acceptance Tests (./test.sh). See lifecycle-test/README.md.
# Cases land when Park and Teardown are implemented.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CASE_DIR="${REPO_ROOT}/lifecycle-test"

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "Lifecycle Tests are scaffolded; no cases yet."
echo "See ${CASE_DIR}/README.md — use ./test.sh for non-destructive Acceptance Tests."

shopt -s nullglob
cases=("${CASE_DIR}"/[0-9]*.sh)
if [[ ${#cases[@]} -eq 0 ]]; then
  echo "No Lifecycle Test cases found — nothing to run."
  exit 0
fi

fail "Lifecycle Test cases exist but the runner is not implemented yet"
