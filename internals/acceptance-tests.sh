#!/usr/bin/env bash
# Acceptance Test runner — Applied Stack external behavior after Apply (./apply.sh).
# Builds fixture once, runs acceptance-tests/[0-9]*.sh as subprocesses in sort order (fail-fast).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/acceptance-tests.sh [--env <slug>] [selector]   e.g. ./internals/acceptance-tests.sh 70-podman
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
TEST_DIR="${REPO_ROOT}/internals/acceptance-tests"
# shellcheck source=acceptance-tests/lib.sh
source "${TEST_DIR}/lib.sh"
# shellcheck source=internals/lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"

"${REPO_ROOT}/internals/lib/check-stack-names.sh"
"${REPO_ROOT}/internals/lib/check-cloud-init-ascii.sh"
"${REPO_ROOT}/internals/lib/check-ssh-port-twins.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"

command -v terraform >/dev/null || fail "terraform not found"
command -v jq >/dev/null || fail "jq not found"
command -v nc >/dev/null || fail "nc not found"
command -v ssh >/dev/null || fail "ssh not found"
command -v ping >/dev/null || fail "ping not found"
command -v curl >/dev/null || fail "curl not found"
require_do_token

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

RESERVED_IP_JSON="$(do_api_get "/v2/reserved_ips/${IP}" | jq -c '.reserved_ip')"
HOST_ID="$(echo "${RESERVED_IP_JSON}" | jq -r '.droplet.id // empty')"
[[ -n "${HOST_ID}" ]] || fail "Reserved IP ${IP} is not attached to a provider Host"
HOST_JSON="$(do_api_get "/v2/droplets/${HOST_ID}" | jq -c '.droplet')"
[[ -n "${HOST_JSON}" && "${HOST_JSON}" != "null" ]] || fail "Host ${HOST_ID} not found at provider"

export IP RESERVED_IP_JSON HOST_JSON REPO_ROOT PLATFORM_ENV
export VERIFY_SSH_IDENTITY="${VERIFY_SSH_IDENTITY:-}"

# Reserved IP survives Host recreate; host keys do not — drop stale known_hosts before any SSH case.
prefect_ssh_forget_host "${IP}"

echo "Checking Reserved IP ${IP} (Environment ${PLATFORM_ENV}) ..."

# Prefect Components for the Platform User (idempotent Component Setup; not Initial Host Provisioning).
"${REPO_ROOT}/internals/ensure-components.sh" --env "${PLATFORM_ENV}"

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
