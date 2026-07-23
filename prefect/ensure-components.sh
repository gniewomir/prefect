#!/usr/bin/env bash
# Ensure Prefect Components on the Host (after Initial Host Provisioning).
# Copies Component source onto the Host Volume, then runs each Component Setup
# in order. Component Setups are idempotent — this entrypoint may be re-run freely.
# Usage: ./prefect/ensure-components.sh
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"
# Hardcoded order: Service Network before Edge (ADR-0010).
COMPONENTS=(network edge)

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar not found" >&2; exit 1; }

cd "${STACK_DIR}"
IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || { echo "no reserved_ip output (apply the Stack first)" >&2; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

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
ssh "${SSH_OPTS[@]}" "root@${IP}" "PREFECT_USER=${USER_NAME} bash -s" <"${CARRIER_READY}"

# Stage Component trees plus shared Host-local lib (sourced by Component Setup).
COPYFILE_DISABLE=1 tar --format=ustar -C "${REPO_ROOT}/prefect" -cf - \
  lib "${COMPONENTS[@]}" \
  | ssh "${SSH_OPTS[@]}" "root@${IP}" "cat > /tmp/prefect-components.tar"

ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s -- "${USER_NAME}" "${COMPONENTS[@]}" <<'REMOTE'
set -euo pipefail
USER_NAME="$1"
shift
COMPONENTS=("$@")

COMPONENTS_ROOT=/var/lib/prefect/components
DATA_ROOT=/var/lib/prefect/components_data

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}" /tmp/prefect-components.tar' EXIT
tar -C "${STAGE}" -xf /tmp/prefect-components.tar

mkdir -p "${COMPONENTS_ROOT}" "${DATA_ROOT}"
rm -rf "${COMPONENTS_ROOT}/lib"
cp -a "${STAGE}/lib" "${COMPONENTS_ROOT}/lib"

for component in "${COMPONENTS[@]}"; do
  rm -rf "${COMPONENTS_ROOT:?}/${component}"
  cp -a "${STAGE}/${component}" "${COMPONENTS_ROOT}/${component}"
  chmod a+x "${COMPONENTS_ROOT}/${component}/setup.sh"
done

# Mount root stays root-owned; everything under it is Prefect User–owned.
chown -R "${USER_NAME}:${USER_NAME}" "${COMPONENTS_ROOT}" "${DATA_ROOT}"

for component in "${COMPONENTS[@]}"; do
  echo "Running Component Setup: ${component}" >&2
  PREFECT_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${component}/setup.sh"
done
REMOTE

echo "Components ensured for Prefect User '${USER_NAME}' on ${IP}."
