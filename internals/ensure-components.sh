#!/usr/bin/env bash
# Ensure Fabric then Components on the Host after Initial Host Provisioning.
# Waits for IHP Done (Host is Substrate), ships Fabric + Component source and the ACME
# want-list via Host delivery, then runs Fabric Setup (Service Network) followed by
# Component Setup (Edge). Setups are idempotent — this entrypoint may be re-run freely.
# Entrypoint name kept; Host messages use ADR-0040 vocabulary (ADR-0010 amended by 0040).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/ensure-components.sh [--env <slug>]
# Optional: PLATFORM_USER=platform
# Requires: Operator Configuration private key path (PROPRAETOR_PRIVATE_KEY_PATH).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
# Hardcoded order: Fabric (Service Network) before Component (Edge) — ADR-0040 / ADR-0010.
FABRIC=(network)
COMPONENTS=(edge)
HOST_SCRIPT="${REPO_ROOT}/internals/components/lib/ensure-components-host.sh"
# shellcheck source=lib/cli.sh
source "${REPO_ROOT}/internals/lib/cli.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/domains.sh
source "${REPO_ROOT}/internals/lib/domains.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"
# shellcheck source=lib/host-delivery.sh
source "${REPO_ROOT}/internals/lib/host-delivery.sh"
# shellcheck source=lib/ihp.sh
source "${REPO_ROOT}/internals/lib/ihp.sh"
# shellcheck source=lib/operator-dotenv.sh
source "${REPO_ROOT}/internals/lib/operator-dotenv.sh"
# shellcheck source=lib/operator-configuration.sh
source "${REPO_ROOT}/internals/lib/operator-configuration.sh"

operator_dotenv_load "${REPO_ROOT}" || exit 1
operator_configuration_require private || exit 1

CLI_env=""
cli_operator_parse CLI -- "$@" || exit 1
environment_activate "${STACK_DIR}" "${CLI_env}" || exit 1

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

for name in "${FABRIC[@]}" "${COMPONENTS[@]}"; do
  [[ -d "${REPO_ROOT}/internals/components/${name}" ]] || {
    echo "Setup tree missing: internals/components/${name}" >&2
    exit 1
  }
  [[ -f "${REPO_ROOT}/internals/components/${name}/setup.sh" ]] || {
    echo "Setup script missing: internals/components/${name}/setup.sh" >&2
    exit 1
  }
done

# Host-local IHP Done gate (Substrate) before Fabric Setup — ADR-0040 / ADR-0030.
host_wait_until_ihp_done "${IHP_DONE}" "${USER_NAME}"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/platform-ensure-stage.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT

# Domain-derived ACME want-list (ADR-0023): stage FQDNs into the delivery payload;
# Host half places the Edge handoff path; Edge Component Setup installs the Host want-list.
domains_acme_fqdns_for "${PLATFORM_ENV}" >"${STAGE}/platform-acme-want-list"

cp -a "${REPO_ROOT}/internals/components/lib" "${STAGE}/lib"
cp "${HOST_SCRIPT}" "${STAGE}/ensure-components-host.sh"
for name in "${FABRIC[@]}" "${COMPONENTS[@]}"; do
  cp -a "${REPO_ROOT}/internals/components/${name}" "${STAGE}/${name}"
done

REMOTE_ROOT="/tmp/platform-ensure-components"
remote_cmd="bash ${REMOTE_ROOT}/ensure-components-host.sh ${USER_NAME}"
for name in "${FABRIC[@]}"; do
  remote_cmd+=" --fabric ${name}"
done
for name in "${COMPONENTS[@]}"; do
  remote_cmd+=" --component ${name}"
done
host_delivery_run "${STAGE}" "${REMOTE_ROOT}" "${remote_cmd}"

echo "Fabric and Components ensured for Platform User '${USER_NAME}' on ${IP}."
