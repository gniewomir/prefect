#!/usr/bin/env bash
# Host-local half of ensure-components. Invoked after Host delivery unpacks the stage.
# Installs staged Component trees onto the Host Volume, places the staged ACME want-list
# at the Edge-owned handoff path, then runs each Component Setup (ADR-0010 / ADR-0023).
# Usage: ensure-components-host.sh <platform-user> <component> [<component> ...]
set -euo pipefail

USER_NAME="${1:?ensure-components-host requires Platform User}"
shift
[[ $# -gt 0 ]] || {
  echo "ensure-components-host: at least one Component name required" >&2
  exit 1
}
COMPONENTS=("$@")

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_ROOT=/var/lib/host-volume/components
DATA_ROOT=/var/lib/host-volume/components_data
WANT_STAGE="${HERE}/platform-acme-want-list"
WANT_HANDOFF=/tmp/platform-acme-want-list

[[ -f "${WANT_STAGE}" ]] || {
  echo "ensure-components: staged ACME FQDN list missing at ${WANT_STAGE}" >&2
  exit 1
}
cp "${WANT_STAGE}" "${WANT_HANDOFF}"
trap 'rm -f "${WANT_HANDOFF}"' EXIT

mkdir -p "${COMPONENTS_ROOT}" "${DATA_ROOT}"
rm -rf "${COMPONENTS_ROOT:?}/lib"
cp -a "${HERE}/lib" "${COMPONENTS_ROOT}/lib"

for component in "${COMPONENTS[@]}"; do
  [[ -d "${HERE}/${component}" ]] || {
    echo "ensure-components: staged Component missing: ${component}" >&2
    exit 1
  }
  [[ -f "${HERE}/${component}/setup.sh" ]] || {
    echo "ensure-components: staged Component Setup missing: ${component}/setup.sh" >&2
    exit 1
  }
  rm -rf "${COMPONENTS_ROOT:?}/${component}"
  cp -a "${HERE}/${component}" "${COMPONENTS_ROOT}/${component}"
  chmod a+x "${COMPONENTS_ROOT}/${component}/setup.sh"
done

# Mount root stays root-owned; everything under it is Platform User–owned.
chown -R "${USER_NAME}:${USER_NAME}" "${COMPONENTS_ROOT}" "${DATA_ROOT}"

# Fail closed if Domain FQDN handoff is missing before Component Setup (Edge places Host path).
[[ -f "${WANT_HANDOFF}" ]] || {
  echo "ensure-components: staged ACME FQDN list missing at ${WANT_HANDOFF}" >&2
  exit 1
}

for component in "${COMPONENTS[@]}"; do
  echo "Running Component Setup: ${component}" >&2
  PLATFORM_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${component}/setup.sh"
done
