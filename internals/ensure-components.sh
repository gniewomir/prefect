#!/usr/bin/env bash
# Ensure Propraetor Components on the Host (after Initial Host Provisioning).
# Copies Component source onto the Host Volume, then runs each Component Setup
# in order. Component Setups are idempotent — this entrypoint may be re-run freely.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./internals/ensure-components.sh [--env <slug>]
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PLATFORM_USER=platform
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
# Hardcoded order: Service Network before Edge (ADR-0010).
COMPONENTS=(network edge)
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=lib/domains.sh
source "${REPO_ROOT}/internals/lib/domains.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"

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

IHP_DONE="${REPO_ROOT}/internals/components/lib/wait-until-ihp-done.sh"
QUADLET_SESSION="${REPO_ROOT}/internals/components/lib/quadlet-user-session.sh"
[[ -f "${IHP_DONE}" ]] || {
  echo "missing ${IHP_DONE}" >&2
  exit 1
}
[[ -f "${QUADLET_SESSION}" ]] || {
  echo "missing ${QUADLET_SESSION}" >&2
  exit 1
}

for component in "${COMPONENTS[@]}"; do
  [[ -d "${REPO_ROOT}/internals/components/${component}" ]] || {
    echo "Component directory missing: internals/components/${component}" >&2
    exit 1
  }
  [[ -f "${REPO_ROOT}/internals/components/${component}/setup.sh" ]] || {
    echo "Component Setup missing: internals/components/${component}/setup.sh" >&2
    exit 1
  }
done

# Host-local IHP Done gate (IHP done, floor, Platform User, Host Volume mount).
host_ssh "PLATFORM_USER=${USER_NAME} bash -s" <"${IHP_DONE}"

# Domain-derived ACME want-list (ADR-0023): stage FQDNs only; Edge Setup places Host path.
WANT_TMP="$(mktemp "${TMPDIR:-/tmp}/platform-acme-want.XXXXXX")"
domains_acme_fqdns_for "${PLATFORM_ENV}" >"${WANT_TMP}"
host_scp "${WANT_TMP}" /tmp/platform-acme-want-list
rm -f "${WANT_TMP}"

# Stage Component trees plus shared Host-local lib (sourced by Component Setup).
COPYFILE_DISABLE=1 tar --format=ustar -C "${REPO_ROOT}/internals/components" -cf - \
  lib "${COMPONENTS[@]}" \
  | host_ssh "cat > /tmp/platform-components.tar"

host_ssh bash -s -- "${USER_NAME}" "${COMPONENTS[@]}" <<'REMOTE'
set -euo pipefail
USER_NAME="$1"
shift
COMPONENTS=("$@")

COMPONENTS_ROOT=/var/lib/host-volume/components
DATA_ROOT=/var/lib/host-volume/components_data

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/platform-components.XXXXXX")"
trap 'rm -rf "${STAGE}" /tmp/platform-components.tar /tmp/platform-acme-want-list' EXIT
tar -C "${STAGE}" -xf /tmp/platform-components.tar

mkdir -p "${COMPONENTS_ROOT}" "${DATA_ROOT}"
rm -rf "${COMPONENTS_ROOT}/lib"
cp -a "${STAGE}/lib" "${COMPONENTS_ROOT}/lib"

for component in "${COMPONENTS[@]}"; do
  rm -rf "${COMPONENTS_ROOT:?}/${component}"
  cp -a "${STAGE}/${component}" "${COMPONENTS_ROOT}/${component}"
  chmod a+x "${COMPONENTS_ROOT}/${component}/setup.sh"
done

# Mount root stays root-owned; everything under it is Platform User–owned.
chown -R "${USER_NAME}:${USER_NAME}" "${COMPONENTS_ROOT}" "${DATA_ROOT}"

# Fail closed if Domain FQDN stage is missing before Component Setup (Edge places Host path).
[[ -f /tmp/platform-acme-want-list ]] || {
  echo "ensure-components: staged ACME FQDN list missing at /tmp/platform-acme-want-list" >&2
  exit 1
}

for component in "${COMPONENTS[@]}"; do
  echo "Running Component Setup: ${component}" >&2
  PLATFORM_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${component}/setup.sh"
done
REMOTE

echo "Components ensured for Platform User '${USER_NAME}' on ${IP}."
