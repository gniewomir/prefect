#!/usr/bin/env bash
# Workload Setup — apply one Workload from the Environment tree on the Host (after Components).
# Idempotent: identical Host Volume SoT (and Intent run unit files when required) → noop (ADR-0033).
# Does not wait for ACME issuance. Does not heal crashed pods.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/workload-setup.sh [--env <slug>] <workload-name>
# Resolves to environments/<slug>/<name>/ (fail closed). Identity = directory basename (ADR-0024).
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PLATFORM_USER=platform
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
HOST_SCRIPT="${REPO_ROOT}/internals/components/lib/workload-setup-host.sh"
QUADLETS_LIB="${REPO_ROOT}/internals/components/lib/workload-quadlets-host.sh"
ENV_HOST_LIB="${REPO_ROOT}/internals/components/lib/workload-environment-host.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/environment-configuration.sh
source "${REPO_ROOT}/internals/lib/environment-configuration.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"

[[ $# -eq 1 ]] || {
  echo "Usage: $0 [--env <slug>] <workload-name>" >&2
  exit 1
}
WL_NAME="$1"

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
[[ -f "${QUADLETS_LIB}" ]] || {
  echo "missing ${QUADLETS_LIB}" >&2
  exit 1
}
[[ -f "${ENV_HOST_LIB}" ]] || {
  echo "missing ${ENV_HOST_LIB}" >&2
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

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

RESOLVED_LOCAL="${STAGE}/environment.resolved"
resolve_out="$(environment_configuration_resolve "${MANIFEST_ABS}" "${ENV_DIR}" "${RESOLVED_LOCAL}")" || exit 1
eval "${resolve_out}"
environment_configuration_require_containers "${MANIFEST_DIR}" "${WL_ENV_ACTIVE}" || exit 1

cp "${HOST_SCRIPT}" "${STAGE}/workload-setup-host.sh"
cp "${QUADLETS_LIB}" "${STAGE}/workload-quadlets-host.sh"
cp "${ENV_HOST_LIB}" "${STAGE}/workload-environment-host.sh"
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

WL_ENV_RESOLVED_REMOTE=""
if [[ "${WL_ENV_ACTIVE}" == "1" ]]; then
  [[ -f "${RESOLVED_LOCAL}" ]] || {
    echo "Environment Configuration resolve produced no file" >&2
    exit 1
  }
  WL_ENV_RESOLVED_REMOTE="/tmp/platform-workload-setup/environment.resolved"
fi

COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf - . \
  | host_ssh "rm -rf /tmp/platform-workload-setup && mkdir -p /tmp/platform-workload-setup && tar -C /tmp/platform-workload-setup -xf -"

host_ssh \
  "PLATFORM_USER=${USER_NAME} WL_ENV_RESOLVED=${WL_ENV_RESOLVED_REMOTE} bash /tmp/platform-workload-setup/workload-setup-host.sh /tmp/platform-workload-setup/${WL_NAME}"

echo "Workload Setup finished on ${IP}."
