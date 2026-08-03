#!/usr/bin/env bash
# Host-local half of ensure-components. Invoked after Host delivery unpacks the stage.
# Installs staged Component trees onto the Host Volume, places the staged ACME want-list
# at the Edge-owned handoff path, ships host-scripts, then applies Component Setup
# (ADR-0040 / ADR-0010 / ADR-0041 / ADR-0023 / #155). Does not install Fabric.
# Usage:
#   ensure-components-host.sh <platform-user> [--component <name>]...
set -euo pipefail

USER_NAME="${1:?ensure-components-host requires Platform User}"
shift

COMPONENTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --component)
      [[ $# -ge 2 ]] || {
        echo "ensure-components-host: --component requires a name" >&2
        exit 1
      }
      COMPONENTS+=("$2")
      shift 2
      ;;
    *)
      echo "ensure-components-host: unknown argument: $1 (want --component)" >&2
      exit 1
      ;;
  esac
done

[[ ${#COMPONENTS[@]} -gt 0 ]] || {
  echo "ensure-components-host: at least one --component required" >&2
  exit 1
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HV_ROOT=/var/lib/host-volume
INTERNALS_ROOT="${HV_ROOT}/internals"
DATA_ROOT="${HV_ROOT}/data"
COMPONENTS_ROOT="${INTERNALS_ROOT}/components"
HOST_SCRIPTS_ROOT="${INTERNALS_ROOT}/host-scripts"
WANT_STAGE="${HERE}/platform-acme-want-list"
WANT_HANDOFF=/tmp/platform-acme-want-list
# shellcheck source=lib/sync-tree-host.sh
source "${HERE}/lib/sync-tree-host.sh"

[[ -f "${WANT_STAGE}" ]] || {
  echo "ensure-components: staged ACME FQDN list missing at ${WANT_STAGE}" >&2
  exit 1
}
cp "${WANT_STAGE}" "${WANT_HANDOFF}"
trap 'rm -f "${WANT_HANDOFF}"' EXIT

# Hard cut (ADR-0018 / ADR-0041): retire components/ + components_data/.
rm -rf "${HV_ROOT:?}/components" "${HV_ROOT:?}/components_data"

mkdir -p \
  "${COMPONENTS_ROOT}" \
  "${INTERNALS_ROOT}/workloads" \
  "${HOST_SCRIPTS_ROOT}" \
  "${DATA_ROOT}/components" \
  "${DATA_ROOT}/workloads"

# Host-executable helpers ship under internals/host-scripts (ADR-0041).
[[ -d "${HERE}/lib" ]] || {
  echo "ensure-components: staged host-scripts lib missing" >&2
  exit 1
}
sync_tree_inplace "${HERE}/lib" "${HOST_SCRIPTS_ROOT}/lib"

install_component_tree() {
  local name="$1"
  [[ -d "${HERE}/${name}" ]] || {
    echo "ensure-components: staged Component tree missing: ${name}" >&2
    exit 1
  }
  [[ -f "${HERE}/${name}/setup.sh" ]] || {
    echo "ensure-components: staged Component Setup missing: ${name}/setup.sh" >&2
    exit 1
  }
  sync_tree_inplace "${HERE}/${name}" "${COMPONENTS_ROOT}/${name}"
  chmod a+x "${COMPONENTS_ROOT}/${name}/setup.sh"
}

for name in "${COMPONENTS[@]}"; do
  install_component_tree "${name}"
done

# Mount root stays root-owned; everything under it is Platform User–owned.
chown -R "${USER_NAME}:${USER_NAME}" "${INTERNALS_ROOT}" "${DATA_ROOT}"

# Fail closed if Domain FQDN handoff is missing before Edge Component Setup.
[[ -f "${WANT_HANDOFF}" ]] || {
  echo "ensure-components: staged ACME FQDN list missing at ${WANT_HANDOFF}" >&2
  exit 1
}

for name in "${COMPONENTS[@]}"; do
  echo "Running Component Setup: ${name}" >&2
  PLATFORM_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${name}/setup.sh"
done
