#!/usr/bin/env bash
# Ensure the Prefect User for rootless Quadlets.
# Outside Initial Host Provisioning (not cloud-init): run after the Stack is applied.
# Usage: ./prefect/ensure-prefect-user.sh
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }

cd "${STACK_DIR}"
IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || { echo "no reserved_ip output (apply the Stack first)" >&2; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s -- "${USER_NAME}" <<'REMOTE'
set -euo pipefail
USER_NAME="$1"
if ! id "${USER_NAME}" >/dev/null 2>&1; then
  useradd --create-home --user-group --shell /bin/bash "${USER_NAME}"
fi
loginctl enable-linger "${USER_NAME}"
REMOTE

echo "Prefect User '${USER_NAME}' ensured on ${IP} (linger enabled)."
