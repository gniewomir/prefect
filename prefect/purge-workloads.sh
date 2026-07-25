#!/usr/bin/env bash
# Purge — permanently remove every Workload whose Intent is trash and its associated data.
# Does not affect Workloads whose Intent is run or stop.
# Usage: ./prefect/purge-workloads.sh
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"
HOST_SCRIPT="${REPO_ROOT}/prefect/lib/purge-workloads-host.sh"

[[ -f "${HOST_SCRIPT}" ]] || {
  echo "missing ${HOST_SCRIPT}" >&2
  exit 1
}

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }

cd "${STACK_DIR}"
IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || { echo "no reserved_ip output (apply the Stack first)" >&2; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp "${HOST_SCRIPT}" "${STAGE}/purge-workloads-host.sh"

COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf - . \
  | ssh "${SSH_OPTS[@]}" "root@${IP}" "rm -rf /tmp/prefect-purge && mkdir -p /tmp/prefect-purge && tar -C /tmp/prefect-purge -xf -"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "PREFECT_USER=${USER_NAME} bash /tmp/prefect-purge/purge-workloads-host.sh"

echo "Purge completed on ${IP}."
