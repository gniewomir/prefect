#!/usr/bin/env bash
# Purge — permanently remove every Workload whose Intent is trash and its Workload-associated data
# (units, Host Volume Workload tree including Route Declaration SoT). Does not write Edge Route
# interior (Edge Component Setup gather drops fulfillment). Does not delete Domains or
# Domain-scoped certificate material. Does not affect Workloads whose Intent is run or stop.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/purge-workloads.sh [--env <slug>]
# Optional: PLATFORM_USER=platform
# Requires: Operator Configuration private key path (PROPRAETOR_PRIVATE_KEY_PATH).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
HOST_SCRIPT="${REPO_ROOT}/internals/components/lib/purge-workloads-host.sh"
UNITS_LIB="${REPO_ROOT}/internals/components/lib/workload-units-host.sh"
QUADLETS_LIB="${REPO_ROOT}/internals/components/lib/workload-quadlets-host.sh"
UNIT_CONSUMERS_LIB="${REPO_ROOT}/internals/components/lib/unit-consumers-host.sh"
ENV_HOST_LIB="${REPO_ROOT}/internals/components/lib/workload-environment-host.sh"
QUADLET_SESSION_LIB="${REPO_ROOT}/internals/components/lib/quadlet-user-session.sh"
# shellcheck source=lib/cli.sh
source "${REPO_ROOT}/internals/lib/cli.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"
# shellcheck source=lib/host-delivery.sh
source "${REPO_ROOT}/internals/lib/host-delivery.sh"
# shellcheck source=lib/operator-dotenv.sh
source "${REPO_ROOT}/internals/lib/operator-dotenv.sh"
# shellcheck source=lib/operator-configuration.sh
source "${REPO_ROOT}/internals/lib/operator-configuration.sh"

operator_dotenv_load "${REPO_ROOT}" || exit 1
operator_configuration_require private || exit 1

CLI_env=""
cli_operator_parse CLI -- "$@" || exit 1
environment_activate "${STACK_DIR}" "${CLI_env}" || exit 1

[[ -f "${HOST_SCRIPT}" ]] || {
  echo "missing ${HOST_SCRIPT}" >&2
  exit 1
}
[[ -f "${UNITS_LIB}" ]] || {
  echo "missing ${UNITS_LIB}" >&2
  exit 1
}
[[ -f "${QUADLETS_LIB}" ]] || {
  echo "missing ${QUADLETS_LIB}" >&2
  exit 1
}
[[ -f "${UNIT_CONSUMERS_LIB}" ]] || {
  echo "missing ${UNIT_CONSUMERS_LIB}" >&2
  exit 1
}
[[ -f "${ENV_HOST_LIB}" ]] || {
  echo "missing ${ENV_HOST_LIB}" >&2
  exit 1
}
[[ -f "${QUADLET_SESSION_LIB}" ]] || {
  echo "missing ${QUADLET_SESSION_LIB}" >&2
  exit 1
}

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/platform-purge-stage.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT
cp "${HOST_SCRIPT}" "${STAGE}/purge-workloads-host.sh"
cp "${UNITS_LIB}" "${STAGE}/workload-units-host.sh"
cp "${QUADLETS_LIB}" "${STAGE}/workload-quadlets-host.sh"
cp "${UNIT_CONSUMERS_LIB}" "${STAGE}/unit-consumers-host.sh"
cp "${ENV_HOST_LIB}" "${STAGE}/workload-environment-host.sh"
cp "${QUADLET_SESSION_LIB}" "${STAGE}/quadlet-user-session.sh"

host_delivery_run "${STAGE}" "/tmp/platform-purge" \
  "PLATFORM_USER=${USER_NAME} bash /tmp/platform-purge/purge-workloads-host.sh"

echo "Purge completed on ${IP}."
