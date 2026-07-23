#!/usr/bin/env bash
# Workload Setup — apply one Workload Manifest on the Host (after Components are ensured).
# Idempotent for the same Manifest. Does not wait for ACME issuance.
# Usage: ./prefect/workload-setup.sh /path/to/manifest.json
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"
HOST_SCRIPT="${REPO_ROOT}/prefect/lib/workload-setup-host.sh"

[[ $# -eq 1 ]] || {
  echo "Usage: $0 /path/to/manifest.json" >&2
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

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

cd "${STACK_DIR}"
IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || { echo "no reserved_ip output (apply the Stack first)" >&2; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

# Resolve optional interior relative to the Manifest directory.
MANIFEST_DIR="$(cd "$(dirname "${MANIFEST_PATH}")" && pwd)"
MANIFEST_ABS="${MANIFEST_DIR}/$(basename "${MANIFEST_PATH}")"
INTERIOR_REL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("interior") or "")' "${MANIFEST_ABS}")"
INTERIOR_ABS=""
if [[ -n "${INTERIOR_REL}" ]]; then
  if [[ "${INTERIOR_REL}" = /* ]]; then
    INTERIOR_ABS="${INTERIOR_REL}"
  else
    INTERIOR_ABS="${MANIFEST_DIR}/${INTERIOR_REL}"
  fi
  [[ -f "${INTERIOR_ABS}" ]] || {
    echo "interior file not found: ${INTERIOR_ABS}" >&2
    exit 1
  }
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp "${MANIFEST_ABS}" "${STAGE}/manifest.json"
cp "${HOST_SCRIPT}" "${STAGE}/workload-setup-host.sh"
if [[ -n "${INTERIOR_ABS}" ]]; then
  cp "${INTERIOR_ABS}" "${STAGE}/interior.conf"
fi

COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf - . \
  | ssh "${SSH_OPTS[@]}" "root@${IP}" "rm -rf /tmp/prefect-workload-setup && mkdir -p /tmp/prefect-workload-setup && tar -C /tmp/prefect-workload-setup -xf -"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "PREFECT_USER=${USER_NAME} bash /tmp/prefect-workload-setup/workload-setup-host.sh /tmp/prefect-workload-setup"

echo "Workload Setup applied on ${IP}."
