#!/usr/bin/env bash
# Lifecycle Test runner — Park / Apply-after-Park / Teardown (destructive; opt-in).
# Not Acceptance Tests (./test.sh). See lifecycle-test/README.md.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./lifecycle-test.sh [--env <slug>] [selector]   e.g. ./lifecycle-test.sh park-apply
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key
# Requires: terraform; curl; jq; ssh; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CASE_DIR="${REPO_ROOT}/lifecycle-test"
STACK_DIR="${REPO_ROOT}/terraform"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"

command -v terraform >/dev/null || fail "terraform not found"
command -v curl >/dev/null || fail "curl not found"
command -v jq >/dev/null || fail "jq not found"
command -v ssh >/dev/null || fail "ssh not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"
[[ -d "${STACK_DIR}" ]] || fail "missing Stack dir ${STACK_DIR}"

export REPO_ROOT STACK_DIR PREFECT_ENV
export VERIFY_SSH_IDENTITY="${VERIFY_SSH_IDENTITY:-}"

ALL_CASES=()
while IFS= read -r case_path; do
  [[ -n "${case_path}" ]] || continue
  ALL_CASES+=("${case_path}")
done < <(find "${CASE_DIR}" -maxdepth 1 -type f -name '[0-9]*.sh' | sort)

[[ ${#ALL_CASES[@]} -gt 0 ]] || fail "no Lifecycle Test cases found in ${CASE_DIR}"

CASES=()
if [[ $# -eq 0 ]]; then
  CASES=("${ALL_CASES[@]}")
else
  SELECTOR="$1"
  for case_path in "${ALL_CASES[@]}"; do
    base="$(basename "${case_path}")"
    if [[ "${base}" == *"${SELECTOR}"* ]]; then
      CASES+=("${case_path}")
    fi
  done
  [[ ${#CASES[@]} -gt 0 ]] || fail "no Lifecycle Test matches selector: ${SELECTOR}"
  if [[ ${#CASES[@]} -ne 1 ]]; then
    matched=""
    for case_path in "${CASES[@]}"; do
      matched+=" $(basename "${case_path}")"
    done
    fail "selector ${SELECTOR} matched multiple cases:${matched}"
  fi
fi

echo "Lifecycle Tests (destructive; may leave Stack Parked or empty)."
echo "Environment: ${PREFECT_ENV}"
echo "Cases: ${#CASES[@]} — see ${CASE_DIR}/README.md"
echo

needs_teardown_confirm=false
for case_path in "${CASES[@]}"; do
  base="$(basename "${case_path}")"
  if [[ "${base}" == *teardown* || "${base}" == *additive* ]]; then
    needs_teardown_confirm=true
    break
  fi
done

if [[ "${needs_teardown_confirm}" == true ]]; then
  echo "WARNING: selected cases include Teardown (full wipe including Durables),"
  echo "         or Additive Domain cleanup that Teardowns then re-Applies."
  echo "         Billing for Reserved IP, Host Volume, and Domain stops during Teardown."
  echo
  printf "Type exactly 'teardown' to run those Lifecycle cases: "
  read -r confirm
  [[ "${confirm}" == "teardown" ]] || fail "aborted (expected exact 'teardown')"
  echo
fi

for case_path in "${CASES[@]}"; do
  echo "--- $(basename "${case_path}") ---"
  bash "${case_path}" || fail "Lifecycle Test failed: $(basename "${case_path}")"
done

echo "All Lifecycle Tests passed."
