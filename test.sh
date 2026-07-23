#!/usr/bin/env bash
# Acceptance Test runner — Applied Stack external behavior after terraform apply.
# Builds fixture once, runs test/[0-9]*.sh as subprocesses in sort order (fail-fast).
# Usage: ./test.sh [selector]   e.g. ./test.sh 70-podman
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
TEST_DIR="${REPO_ROOT}/test"
# shellcheck source=test/lib.sh
source "${TEST_DIR}/lib.sh"

command -v terraform >/dev/null || fail "terraform not found"
command -v jq >/dev/null || fail "jq not found"
command -v nc >/dev/null || fail "nc not found"
command -v ssh >/dev/null || fail "ssh not found"
command -v ping >/dev/null || fail "ping not found"

cd "${STACK_DIR}"

IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (apply the Stack first)"

STATE_JSON="$(terraform show -json)"
HOST_JSON="$(echo "${STATE_JSON}" | jq -c '
  .values.root_module.resources[]
  | select(.type == "digitalocean_droplet" and .name == "web")
  | .values
')"
[[ -n "${HOST_JSON}" && "${HOST_JSON}" != "null" ]] || fail "Host digitalocean_droplet.web not in State"

export IP STATE_JSON HOST_JSON
export VERIFY_SSH_IDENTITY="${VERIFY_SSH_IDENTITY:-}"

echo "Checking Reserved IP ${IP} ..."

ALL_CASES=()
while IFS= read -r case_path; do
  [[ -n "${case_path}" ]] || continue
  ALL_CASES+=("${case_path}")
done < <(find "${TEST_DIR}" -maxdepth 1 -type f -name '[0-9]*.sh' | sort)

[[ ${#ALL_CASES[@]} -gt 0 ]] || fail "no Acceptance Tests found in ${TEST_DIR}"

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
  [[ ${#CASES[@]} -gt 0 ]] || fail "no Acceptance Test matches selector: ${SELECTOR}"
  if [[ ${#CASES[@]} -ne 1 ]]; then
    matched=""
    for case_path in "${CASES[@]}"; do
      matched+=" $(basename "${case_path}")"
    done
    fail "selector ${SELECTOR} matched multiple cases:${matched}"
  fi
fi

for case_path in "${CASES[@]}"; do
  echo "--- $(basename "${case_path}") ---"
  bash "${case_path}" || fail "Acceptance Test failed: $(basename "${case_path}")"
done

echo "All Acceptance Tests passed."
