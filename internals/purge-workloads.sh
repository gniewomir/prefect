#!/usr/bin/env bash
# Purge — permanently remove every Workload whose Intent is trash and its Workload-associated data
# (installed Routes, units, Host Volume Workload tree). Does not delete Domains or Domain-scoped
# certificate material. Does not affect Workloads whose Intent is run or stop.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/purge-workloads.sh [--env <slug>]
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PLATFORM_USER=platform
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
HOST_SCRIPT="${REPO_ROOT}/internals/components/lib/purge-workloads-host.sh"
QUADLETS_LIB="${REPO_ROOT}/internals/components/lib/workload-quadlets-host.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"

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

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp "${HOST_SCRIPT}" "${STAGE}/purge-workloads-host.sh"
cp "${QUADLETS_LIB}" "${STAGE}/workload-quadlets-host.sh"

COPYFILE_DISABLE=1 tar --format=ustar -C "${STAGE}" -cf - . \
  | host_ssh "rm -rf /tmp/platform-purge && mkdir -p /tmp/platform-purge && tar -C /tmp/platform-purge -xf -"

host_ssh \
  "PLATFORM_USER=${USER_NAME} bash /tmp/platform-purge/purge-workloads-host.sh"

echo "Purge completed on ${IP}."
