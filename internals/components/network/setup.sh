#!/usr/bin/env bash
# Fabric Setup for the Service Network (ADR-0040).
# Idempotent: safe to re-run. Success means Fabric (Service Network) is in the correct state.
# Runs on the Host only (no Stack discovery / SSH). Invoked by ensure-components.sh.
# Not a Component — Edge is the Component on the ensure bring-up path.
set -euo pipefail

USER_NAME="${PLATFORM_USER:-platform}"
SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/quadlet-user-session.sh
source "${SRC}/../lib/quadlet-user-session.sh"
# shellcheck source=../lib/component-units-host.sh
source "${SRC}/../lib/component-units-host.sh"

quadlet_user_session_begin

component_units_install "${SRC}"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.config"

quadlet_user_session_reload

[[ -f "${UNIT_DIR}/service-network.network" ]]
