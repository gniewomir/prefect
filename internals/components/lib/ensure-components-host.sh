#!/usr/bin/env bash
# Host-local half of ensure-components. Invoked after Host delivery unpacks the stage.
# Installs staged trees onto the Host Volume, places the staged ACME want-list at the
# Edge-owned handoff path, then applies Fabric Setup then Component Setup (ADR-0040 /
# ADR-0010 / ADR-0023). Service Network is Fabric — not a Component peer of Edge.
# Usage:
#   ensure-components-host.sh <platform-user> \
#     [--fabric <name>]... [--component <name>]...
set -euo pipefail

USER_NAME="${1:?ensure-components-host requires Platform User}"
shift

FABRIC=()
COMPONENTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fabric)
      [[ $# -ge 2 ]] || {
        echo "ensure-components-host: --fabric requires a name" >&2
        exit 1
      }
      FABRIC+=("$2")
      shift 2
      ;;
    --component)
      [[ $# -ge 2 ]] || {
        echo "ensure-components-host: --component requires a name" >&2
        exit 1
      }
      COMPONENTS+=("$2")
      shift 2
      ;;
    *)
      echo "ensure-components-host: unknown argument: $1 (want --fabric / --component)" >&2
      exit 1
      ;;
  esac
done

[[ ${#FABRIC[@]} -gt 0 || ${#COMPONENTS[@]} -gt 0 ]] || {
  echo "ensure-components-host: at least one --fabric or --component required" >&2
  exit 1
}

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

# Install staged source trees (Fabric + Component share Host Volume components/ today).
install_staged_tree() {
  local name="$1"
  [[ -d "${HERE}/${name}" ]] || {
    echo "ensure-components: staged tree missing: ${name}" >&2
    exit 1
  }
  [[ -f "${HERE}/${name}/setup.sh" ]] || {
    echo "ensure-components: staged Setup missing: ${name}/setup.sh" >&2
    exit 1
  }
  rm -rf "${COMPONENTS_ROOT:?}/${name}"
  cp -a "${HERE}/${name}" "${COMPONENTS_ROOT}/${name}"
  chmod a+x "${COMPONENTS_ROOT}/${name}/setup.sh"
}

for name in "${FABRIC[@]}" "${COMPONENTS[@]}"; do
  install_staged_tree "${name}"
done

# Mount root stays root-owned; everything under it is Platform User–owned.
chown -R "${USER_NAME}:${USER_NAME}" "${COMPONENTS_ROOT}" "${DATA_ROOT}"

# Fail closed if Domain FQDN handoff is missing before Edge Component Setup.
[[ -f "${WANT_HANDOFF}" ]] || {
  echo "ensure-components: staged ACME FQDN list missing at ${WANT_HANDOFF}" >&2
  exit 1
}

for name in "${FABRIC[@]}"; do
  echo "Running Fabric Setup: ${name}" >&2
  PLATFORM_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${name}/setup.sh"
done

for name in "${COMPONENTS[@]}"; do
  echo "Running Component Setup: ${name}" >&2
  PLATFORM_USER="${USER_NAME}" "${COMPONENTS_ROOT}/${name}/setup.sh"
done
