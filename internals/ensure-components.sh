#!/usr/bin/env bash
# Ensure Propraetor Components on the Host (after Initial Host Provisioning).
# Ships Component source + ACME want-list via Host delivery, then runs each Component Setup
# in order. Component Setups are idempotent — this entrypoint may be re-run freely.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/ensure-components.sh [--env <slug>]
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PLATFORM_USER=platform
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
# Hardcoded order: Service Network before Edge (ADR-0010).
COMPONENTS=(network edge)
HOST_SCRIPT="${REPO_ROOT}/internals/components/lib/ensure-components-host.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/domains.sh
source "${REPO_ROOT}/internals/lib/domains.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"
# shellcheck source=lib/host-delivery.sh
source "${REPO_ROOT}/internals/lib/host-delivery.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  echo "unknown argument: ${arg} (only optional --env is accepted)" >&2
  exit 1
done

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar not found" >&2; exit 1; }

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

IHP_DONE="${REPO_ROOT}/internals/components/lib/wait-until-ihp-done.sh"
[[ -f "${IHP_DONE}" ]] || {
  echo "missing ${IHP_DONE}" >&2
  exit 1
}
[[ -f "${HOST_SCRIPT}" ]] || {
  echo "missing ${HOST_SCRIPT}" >&2
  exit 1
}

for component in "${COMPONENTS[@]}"; do
  [[ -d "${REPO_ROOT}/internals/components/${component}" ]] || {
    echo "Component directory missing: internals/components/${component}" >&2
    exit 1
  }
  [[ -f "${REPO_ROOT}/internals/components/${component}/setup.sh" ]] || {
    echo "Component Setup missing: internals/components/${component}/setup.sh" >&2
    exit 1
  }
done

# Host-local IHP Done gate (IHP done, floor, Platform User, Host Volume mount).
host_ssh "PLATFORM_USER=${USER_NAME} bash -s" <"${IHP_DONE}"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/platform-ensure-stage.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT

# Domain-derived ACME want-list (ADR-0023): stage FQDNs into the delivery payload;
# Host half places the Edge handoff path; Edge Setup installs the Host want-list.
domains_acme_fqdns_for "${PLATFORM_ENV}" >"${STAGE}/platform-acme-want-list"

cp -a "${REPO_ROOT}/internals/components/lib" "${STAGE}/lib"
cp "${HOST_SCRIPT}" "${STAGE}/ensure-components-host.sh"
for component in "${COMPONENTS[@]}"; do
  cp -a "${REPO_ROOT}/internals/components/${component}" "${STAGE}/${component}"
done

REMOTE_ROOT="/tmp/platform-ensure-components"
remote_cmd="bash ${REMOTE_ROOT}/ensure-components-host.sh ${USER_NAME}"
for component in "${COMPONENTS[@]}"; do
  remote_cmd+=" ${component}"
done
host_delivery_run "${STAGE}" "${REMOTE_ROOT}" "${remote_cmd}"

echo "Components ensured for Platform User '${USER_NAME}' on ${IP}."
