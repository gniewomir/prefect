#!/usr/bin/env bash
# Component Setup for the Edge.
# Idempotent: safe to re-run. Success means this Component is in the correct state.
# Runs on the Host only (no Stack discovery / SSH). Invoked by ensure-components.sh.
set -euo pipefail

USER_NAME="${PREFECT_USER:-prefect}"
SRC="$(cd "$(dirname "$0")" && pwd)"
DATA_ROOT=/var/lib/prefect/components_data/edge
ROUTES_DIR="${DATA_ROOT}/routes"
CERTS_DIR="${DATA_ROOT}/certs"

id "${USER_NAME}" >/dev/null
HOME_DIR="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
UID_NUM="$(id -u "${USER_NAME}")"
UNIT_DIR="${HOME_DIR}/.config/containers/systemd"

mkdir -p "${UNIT_DIR}" "${ROUTES_DIR}" "${CERTS_DIR}"
install -m 0644 "${SRC}/edge.pod" "${UNIT_DIR}/edge.pod"
install -m 0644 "${SRC}/edge-nginx.container" "${UNIT_DIR}/edge-nginx.container"

# Ensure stub only — never wipe other Route files (Workload Setup owns those).
if [[ -f "${SRC}/routes/00-empty.conf" ]]; then
  install -m 0644 "${SRC}/routes/00-empty.conf" "${ROUTES_DIR}/00-empty.conf"
elif ! compgen -G "${ROUTES_DIR}/"*.conf >/dev/null; then
  printf '%s\n' '# no Workload Routes yet' >"${ROUTES_DIR}/00-empty.conf"
fi

chown -R "${USER_NAME}:${USER_NAME}" \
  "${HOME_DIR}/.config" \
  "${DATA_ROOT}"

[[ -f "${SRC}/nginx.conf" ]] || {
  echo "Edge nginx.conf missing at ${SRC}/nginx.conf" >&2
  exit 1
}

systemctl start "user@${UID_NUM}.service"
export XDG_RUNTIME_DIR="/run/user/${UID_NUM}"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -d "${XDG_RUNTIME_DIR}" ]] && break
  sleep 0.5
done
runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" \
  systemctl --user daemon-reload
runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" \
  systemctl --user reset-failed edge-pod.service edge-nginx.service 2>/dev/null || true
# Quadlet: edge.pod → edge-pod.service (pulls Service Network + edge-nginx).
runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" \
  systemctl --user restart edge-pod.service
runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" \
  systemctl --user --quiet is-active edge-pod.service

# Wait until Host :80 returns an HTTP status (image pull + nginx start).
for _ in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
  if [[ "${code}" =~ ^[0-9]{3}$ ]]; then
    exit 0
  fi
  sleep 2
done
echo "Edge did not become reachable on :80 in time" >&2
runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" \
  systemctl --user status edge-pod.service edge-nginx.service --no-pager >&2 || true
exit 1
