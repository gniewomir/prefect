#!/usr/bin/env bash
# Install Service Network + Edge user Quadlets for the Prefect User (not cloud-init).
# Usage: ./prefect/install-edge.sh
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key  PREFECT_USER=prefect
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
USER_NAME="${PREFECT_USER:-prefect}"

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }
command -v ssh >/dev/null || { echo "ssh not found" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar not found" >&2; exit 1; }

cd "${STACK_DIR}"
IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || { echo "no reserved_ip output (apply the Stack first)" >&2; exit 1; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

COPYFILE_DISABLE=1 tar --format=ustar -C "${REPO_ROOT}/prefect" -cf - network edge \
  | ssh "${SSH_OPTS[@]}" "root@${IP}" "cat > /tmp/prefect-edge.tar"

ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s -- "${USER_NAME}" <<'REMOTE'
set -euo pipefail
USER_NAME="$1"

# Edge binds :80 rootless — wait until Initial Host Provisioning has finished and
# the port floor is live (write_files lands before runcmd; mounts lengthen first boot).
echo "Waiting for Initial Host Provisioning..." >&2
set +e
cloud-init status --wait >/dev/null 2>&1
rc=$?
set -e
if [[ ${rc} -ne 0 && ${rc} -ne 2 ]]; then
  echo "Initial Host Provisioning wait failed (exit ${rc})" >&2
  exit 1
fi
sysctl --system >/dev/null 2>&1 || true
floor="$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || true)"
if [[ "${floor}" != "80" ]]; then
  echo "net.ipv4.ip_unprivileged_port_start is '${floor}', expected 80 (ADR-0006)" >&2
  exit 1
fi

id "${USER_NAME}" >/dev/null

HOME_DIR="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
UID_NUM="$(id -u "${USER_NAME}")"
UNIT_DIR="${HOME_DIR}/.config/containers/systemd"
DATA_DIR="${HOME_DIR}/.local/share/prefect/edge"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}" /tmp/prefect-edge.tar' EXIT

tar -C "${STAGE}" -xf /tmp/prefect-edge.tar
mkdir -p "${UNIT_DIR}" "${DATA_DIR}/routes" "${DATA_DIR}/certs"
install -m 0644 "${STAGE}/network/service-network.network" "${UNIT_DIR}/service-network.network"
install -m 0644 "${STAGE}/edge/edge.pod" "${UNIT_DIR}/edge.pod"
install -m 0644 "${STAGE}/edge/edge-nginx.container" "${UNIT_DIR}/edge-nginx.container"
install -m 0644 "${STAGE}/edge/nginx.conf" "${DATA_DIR}/nginx.conf"
if [[ -d "${STAGE}/edge/routes" ]]; then
  find "${STAGE}/edge/routes" -maxdepth 1 -type f -name '*.conf' -exec \
    install -m 0644 {} "${DATA_DIR}/routes/" \;
fi
# nginx rejects wildcard includes with zero matches; keep a comment-only stub when empty.
if ! compgen -G "${DATA_DIR}/routes/"*.conf >/dev/null; then
  printf '%s\n' '# no Workload Routes yet' >"${DATA_DIR}/routes/00-empty.conf"
  chown "${USER_NAME}:${USER_NAME}" "${DATA_DIR}/routes/00-empty.conf"
fi
chown -R "${USER_NAME}:${USER_NAME}" \
  "${HOME_DIR}/.config" \
  "${HOME_DIR}/.local"

systemctl start "user@${UID_NUM}.service"
export XDG_RUNTIME_DIR="/run/user/${UID_NUM}"
# Give user manager a moment to create the runtime dir / bus.
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
REMOTE

echo "Edge installed for Prefect User '${USER_NAME}' on ${IP}."
