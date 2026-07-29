#!/usr/bin/env bash
# Component Setup for the Service Network.
# Idempotent: safe to re-run. Success means this Component is in the correct state.
# Runs on the Host only (no Stack discovery / SSH). Invoked by ensure-components.sh.
set -euo pipefail

USER_NAME="${PLATFORM_USER:-platform}"
SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/quadlet-user-session.sh
source "${SRC}/../lib/quadlet-user-session.sh"

quadlet_user_session_begin

install -m 0644 "${SRC}/service-network.network" "${UNIT_DIR}/service-network.network"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.config"

quadlet_user_session_reload

[[ -f "${UNIT_DIR}/service-network.network" ]]
