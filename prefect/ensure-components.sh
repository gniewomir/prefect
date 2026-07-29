#!/usr/bin/env bash
# Ensure Prefect Components on the Host (after Initial Host Provisioning).
# Copies Component source onto the Host Volume, then runs each Component Setup
# in order. Component Setups are idempotent — this entrypoint may be re-run freely.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./prefect/ensure-components.sh [--env <slug>]
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"
# Hardcoded order: Service Network before Edge (ADR-0010).
COMPONENTS=(network edge)
# shellcheck source=../lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=../lib/domains.sh
source "${REPO_ROOT}/lib/domains.sh"
# shellcheck source=../lib/ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  echo "unknown argument: ${arg} (only optional --env is accepted)" >&2
  exit 1
done

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v scp >/dev/null || { echo "scp not found" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar not found" >&2; exit 1; }

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

CARRIER_READY="${REPO_ROOT}/prefect/lib/wait-until-carrier-ready.sh"
QUADLET_SESSION="${REPO_ROOT}/prefect/lib/quadlet-user-session.sh"
[[ -f "${CARRIER_READY}" ]] || {
  echo "missing ${CARRIER_READY}" >&2
  exit 1
}
[[ -f "${QUADLET_SESSION}" ]] || {
  echo "missing ${QUADLET_SESSION}" >&2
  exit 1
}

for component in "${COMPONENTS[@]}"; do
  [[ -d "${REPO_ROOT}/prefect/${component}" ]] || {
    echo "Component directory missing: prefect/${component}" >&2
    exit 1
  }
  [[ -f "${REPO_ROOT}/prefect/${component}/setup.sh" ]] || {
    echo "Component Setup missing: prefect/${component}/setup.sh" >&2
    exit 1
  }
done

# Host-local carrier gate (IHP done, floor, Prefect User, Host Volume mount).
host_ssh "PREFECT_USER=${USER_NAME} bash -s" <"${CARRIER_READY}"

# Domain-derived ACME want-list (ADR-0023): install before Edge Setup oneshot.
WANT_TMP="$(mktemp)"
domains_acme_fqdns_for "${PREFECT_ENV}" >"${WANT_TMP}"
host_scp "${WANT_TMP}" /tmp/prefect-acme-want-list
rm -f "${WANT_TMP}"

# Stage Component trees plus shared Host-local lib (sourced by Component Setup).
COPYFILE_DISABLE=1 tar --format=ustar -C "${REPO_ROOT}/prefect" -cf - \
  lib "${COMPONENTS[@]}" \
  | host_ssh "cat > /tmp/prefect-components.tar"

host_ssh bash -s -- "${USER_NAME}" "${COMPONENTS[@]}" <<'REMOTE'
set -euo pipefail
USER_NAME="$1"
shift
COMPONENTS=("$@")

COMPONENTS_ROOT=/var/lib/prefect/components
DATA_ROOT=/var/lib/prefect/components_data
ACME_DIR="${DATA_ROOT}/edge/acme"
WANT_LIST="${ACME_DIR}/want-list"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}" /tmp/prefect-components.tar /tmp/prefect-acme-want-list' EXIT
tar -C "${STAGE}" -xf /tmp/prefect-components.tar

mkdir -p "${COMPONENTS_ROOT}" "${DATA_ROOT}" "${ACME_DIR}"
rm -rf "${COMPONENTS_ROOT}/lib"
cp -a "${STAGE}/lib" "${COMPONENTS_ROOT}/lib"

for component in "${COMPONENTS[@]}"; do
  rm -rf "${COMPONENTS_ROOT:?}/${component}"
  cp -a "${STAGE}/${component}" "${COMPONENTS_ROOT}/${component}"
  chmod a+x "${COMPONENTS_ROOT}/${component}/setup.sh"
done

install -m 0644 /tmp/prefect-acme-want-list "${WANT_LIST}"

# Mount root stays root-owned; everything under it is Prefect User–owned.
chown -R "${USER_NAME}:${USER_NAME}" "${COMPONENTS_ROOT}" "${DATA_ROOT}"

for component in "${COMPONENTS[@]}"; do
  echo "Running Component Setup: ${component}" >&2
  PREFECT_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${component}/setup.sh"
done
REMOTE

echo "Components ensured for Prefect User '${USER_NAME}' on ${IP}."
