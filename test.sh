#!/usr/bin/env bash
# Acceptance Test runner — Applied Stack external behavior after Apply (./apply.sh).
# Builds fixture once, runs test/[0-9]*.sh as subprocesses in sort order (fail-fast).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./test.sh [--env <slug>] [selector]   e.g. ./test.sh 70-podman
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
TEST_DIR="${REPO_ROOT}/test"
# shellcheck source=test/lib.sh
source "${TEST_DIR}/lib.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"

"${REPO_ROOT}/lib/check-stack-names.sh"
"${REPO_ROOT}/lib/check-cloud-init-ascii.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"

command -v terraform >/dev/null || fail "terraform not found"
command -v jq >/dev/null || fail "jq not found"
command -v nc >/dev/null || fail "nc not found"
command -v ssh >/dev/null || fail "ssh not found"
command -v ping >/dev/null || fail "ping not found"
command -v curl >/dev/null || fail "curl not found"

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

export IP STATE_JSON HOST_JSON REPO_ROOT PREFECT_ENV
export VERIFY_SSH_IDENTITY="${VERIFY_SSH_IDENTITY:-}"

# Reserved IP survives Host recreate; host keys do not — drop stale known_hosts before any SSH case.
ssh-keygen -R "${IP}" >/dev/null 2>&1 || true

echo "Checking Reserved IP ${IP} (Environment ${PREFECT_ENV}) ..."

# Prefect Components for the Prefect User (idempotent Component Setup; not Initial Host Provisioning).
"${REPO_ROOT}/prefect/ensure-components.sh" --env "${PREFECT_ENV}"

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
