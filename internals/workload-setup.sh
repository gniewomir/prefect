#!/usr/bin/env bash
# Workload Setup — apply one Workload from the Environment tree on the Host (after Components).
# Idempotent: identical Host Volume SoT (and Intent run unit files when required) → noop (ADR-0033).
# Syncs Route Declaration files into Workload SoT only; Edge Component Setup gathers (ADR-0040).
# Does not wait for ACME issuance. Does not heal crashed pods.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/workload-setup.sh <workload-name> [--env <slug>]
# Resolves to environments/<slug>/<name>/ (fail closed). Identity = directory basename (ADR-0024).
# Optional: PLATFORM_USER=platform
# Requires: Operator Configuration private key path (PROPRAETOR_PRIVATE_KEY_PATH).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
HOST_SCRIPT="${REPO_ROOT}/internals/components/lib/workload-setup-host.sh"
UNITS_LIB="${REPO_ROOT}/internals/components/lib/workload-units-host.sh"
QUADLETS_LIB="${REPO_ROOT}/internals/components/lib/workload-quadlets-host.sh"
UNIT_CONSUMERS_LIB="${REPO_ROOT}/internals/components/lib/unit-consumers-host.sh"
ENV_HOST_LIB="${REPO_ROOT}/internals/components/lib/workload-environment-host.sh"
QUADLET_SESSION_LIB="${REPO_ROOT}/internals/components/lib/quadlet-user-session.sh"
# shellcheck source=lib/cli.sh
source "${REPO_ROOT}/internals/lib/cli.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/environment-configuration.sh
source "${REPO_ROOT}/internals/lib/environment-configuration.sh"
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
CLI_workload=""
cli_operator_parse CLI pos:workload:required -- "$@" || {
  echo "Usage: $0 <workload-name> [--env <slug>]" >&2
  exit 1
}
environment_activate "${STACK_DIR}" "${CLI_env}" || exit 1
WL_NAME="${CLI_workload}"

if [[ -z "${WL_NAME}" || "${WL_NAME}" == "." || "${WL_NAME}" == ".." ]] ||
  [[ "${WL_NAME}" == .* ]] ||
  [[ "${WL_NAME}" == */* ]] ||
  [[ "${WL_NAME}" =~ [[:space:]] ]]; then
  echo "workload name must be a single non-hidden path segment: '${WL_NAME}'" >&2
  exit 1
fi

MANIFEST_DIR="${REPO_ROOT}/environments/${PLATFORM_ENV}/${WL_NAME}"
MANIFEST_ABS="${MANIFEST_DIR}/manifest.json"
[[ -d "${MANIFEST_DIR}" ]] || {
  echo "Workload tree not found: environments/${PLATFORM_ENV}/${WL_NAME}/" >&2
  exit 1
}
[[ -f "${MANIFEST_ABS}" ]] || {
  echo "manifest.json missing in environments/${PLATFORM_ENV}/${WL_NAME}/" >&2
  exit 1
}
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
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

ROUTES_SRC="${MANIFEST_DIR}/routes"
QUADLETS_SRC="${MANIFEST_DIR}/quadlets"
SYSTEMD_SRC="${MANIFEST_DIR}/systemd"
ENV_DIR="${REPO_ROOT}/environments/${PLATFORM_ENV}"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/platform-workload-setup-stage.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT

RESOLVED_REMOTE_ROOT="/tmp/platform-workload-setup"
environment_configuration_stage_for_setup \
  "${STAGE}" "${MANIFEST_ABS}" "${ENV_DIR}" "${MANIFEST_DIR}" "${RESOLVED_REMOTE_ROOT}" || exit 1

cp "${HOST_SCRIPT}" "${STAGE}/workload-setup-host.sh"
cp "${UNITS_LIB}" "${STAGE}/workload-units-host.sh"
cp "${QUADLETS_LIB}" "${STAGE}/workload-quadlets-host.sh"
cp "${UNIT_CONSUMERS_LIB}" "${STAGE}/unit-consumers-host.sh"
cp "${ENV_HOST_LIB}" "${STAGE}/workload-environment-host.sh"
cp "${QUADLET_SESSION_LIB}" "${STAGE}/quadlet-user-session.sh"
mkdir -p "${STAGE}/${WL_NAME}"
cp "${MANIFEST_ABS}" "${STAGE}/${WL_NAME}/manifest.json"
if [[ -d "${ROUTES_SRC}" ]]; then
  mkdir -p "${STAGE}/${WL_NAME}/routes"
  for src in "${ROUTES_SRC}"/*; do
    [[ -f "${src}" ]] || continue
    cp "${src}" "${STAGE}/${WL_NAME}/routes/$(basename "${src}")"
  done
fi
if [[ -d "${QUADLETS_SRC}" ]]; then
  mkdir -p "${STAGE}/${WL_NAME}/quadlets"
  for src in "${QUADLETS_SRC}"/*; do
    [[ -f "${src}" ]] || continue
    cp "${src}" "${STAGE}/${WL_NAME}/quadlets/$(basename "${src}")"
  done
fi
if [[ -d "${SYSTEMD_SRC}" ]]; then
  mkdir -p "${STAGE}/${WL_NAME}/systemd"
  for src in "${SYSTEMD_SRC}"/*; do
    [[ -f "${src}" ]] || continue
    cp "${src}" "${STAGE}/${WL_NAME}/systemd/$(basename "${src}")"
  done
fi

host_delivery_run "${STAGE}" "${RESOLVED_REMOTE_ROOT}" \
  "PLATFORM_USER=${USER_NAME} WL_ENV_RESOLVED=${WL_ENV_RESOLVED_REMOTE} bash ${RESOLVED_REMOTE_ROOT}/workload-setup-host.sh ${RESOLVED_REMOTE_ROOT}/${WL_NAME}"

echo "Workload Setup finished on ${IP}."
