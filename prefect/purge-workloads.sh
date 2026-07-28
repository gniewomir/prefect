#!/usr/bin/env bash
# Purge — permanently remove every Workload whose Intent is trash and its Workload-associated data
# (installed Routes, units, Host Volume Workload tree). Does not delete Domains or Domain-scoped
# certificate material. Does not affect Workloads whose Intent is run or stop.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./prefect/purge-workloads.sh [--env <slug>]
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"
HOST_SCRIPT="${REPO_ROOT}/prefect/lib/purge-workloads-host.sh"
QUADLETS_LIB="${REPO_ROOT}/prefect/lib/workload-quadlets-host.sh"
# shellcheck source=../lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=../lib/ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

environment_activate "${STACK_DIR}" "$@" || exit 1
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  echo "unknown argument: ${arg} (only optional --env is accepted)" >&2
  exit 1
done

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

cd "${STACK_DIR}"
IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || { echo "no reserved_ip output (apply the Stack first)" >&2; exit 1; }

SSH_OPTS=(
  -o "Port=${PREFECT_SSH_PORT}"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o PreferredAuthentications=publickey
)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp "${HOST_SCRIPT}" "${STAGE}/purge-workloads-host.sh"
cp "${QUADLETS_LIB}" "${STAGE}/workload-quadlets-host.sh"

COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf - . \
  | ssh "${SSH_OPTS[@]}" "root@${IP}" "rm -rf /tmp/prefect-purge && mkdir -p /tmp/prefect-purge && tar -C /tmp/prefect-purge -xf -"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "PREFECT_USER=${USER_NAME} bash /tmp/prefect-purge/purge-workloads-host.sh"

echo "Purge completed on ${IP}."
