#!/usr/bin/env bash
# Workload Setup — apply one Workload Manifest on the Host (after Components are ensured).
# Idempotent for the same Manifest. Does not wait for ACME issuance.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./prefect/workload-setup.sh [--env <slug>] /path/to/manifest.json
# Workload identity is the basename of the directory containing the Manifest (ADR-0024).
# Optional siblings: routes/ and quadlets/ next to the Manifest.
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"
HOST_SCRIPT="${REPO_ROOT}/prefect/lib/workload-setup-host.sh"
QUADLETS_LIB="${REPO_ROOT}/prefect/lib/workload-quadlets-host.sh"
# shellcheck source=../lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=../lib/ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"

[[ $# -eq 1 ]] || {
  echo "Usage: $0 [--env <slug>] /path/to/manifest.json" >&2
  exit 1
}
MANIFEST_PATH="$1"
[[ -f "${MANIFEST_PATH}" ]] || {
  echo "Manifest not found: ${MANIFEST_PATH}" >&2
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

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

MANIFEST_DIR="$(cd "$(dirname "${MANIFEST_PATH}")" && pwd)"
MANIFEST_ABS="${MANIFEST_DIR}/$(basename "${MANIFEST_PATH}")"
WL_NAME="$(basename "${MANIFEST_DIR}")"
ROUTES_SRC="${MANIFEST_DIR}/routes"
QUADLETS_SRC="${MANIFEST_DIR}/quadlets"

if [[ -z "${WL_NAME}" || "${WL_NAME}" == "." || "${WL_NAME}" == ".." ]] ||
  [[ "${WL_NAME}" =~ [[:space:]] ]]; then
  echo "workload identity (directory basename) must be a single path segment: '${WL_NAME}'" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp "${HOST_SCRIPT}" "${STAGE}/workload-setup-host.sh"
cp "${QUADLETS_LIB}" "${STAGE}/workload-quadlets-host.sh"
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

COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf - . \
  | host_ssh "rm -rf /tmp/prefect-workload-setup && mkdir -p /tmp/prefect-workload-setup && tar -C /tmp/prefect-workload-setup -xf -"

host_ssh \
  "PREFECT_USER=${USER_NAME} bash /tmp/prefect-workload-setup/workload-setup-host.sh /tmp/prefect-workload-setup/${WL_NAME}"

echo "Workload Setup applied on ${IP}."
