#!/usr/bin/env bash
# Component Setup for the Service Network.
# Idempotent: safe to re-run. Success means this Component is in the correct state.
# Runs on the Host only (no Stack discovery / SSH). Invoked by ensure-components.sh.
set -euo pipefail

USER_NAME="${PREFECT_USER:-prefect}"
SRC="$(cd "$(dirname "$0")" && pwd)"

id "${USER_NAME}" >/dev/null
HOME_DIR="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
UID_NUM="$(id -u "${USER_NAME}")"
UNIT_DIR="${HOME_DIR}/.config/containers/systemd"

mkdir -p "${UNIT_DIR}"
install -m 0644 "${SRC}/service-network.network" "${UNIT_DIR}/service-network.network"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.config"

systemctl start "user@${UID_NUM}.service"
export XDG_RUNTIME_DIR="/run/user/${UID_NUM}"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -d "${XDG_RUNTIME_DIR}" ]] && break
  sleep 0.5
done
runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" \
  systemctl --user daemon-reload

[[ -f "${UNIT_DIR}/service-network.network" ]]
