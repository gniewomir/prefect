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
ACME_WWW="${DATA_ROOT}/acme-www"
ACME_DIR="${DATA_ROOT}/acme"
WANT_LIST="${ACME_DIR}/want-list"
# shellcheck source=../lib/quadlet-user-session.sh
source "${SRC}/../lib/quadlet-user-session.sh"

quadlet_user_session_begin
SYSTEMD_USER_DIR="${HOME_DIR}/.config/systemd/user"
mkdir -p "${SYSTEMD_USER_DIR}"

mkdir -p "${ROUTES_DIR}" "${CERTS_DIR}" "${ACME_WWW}" "${ACME_DIR}"
[[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"

install -m 0644 "${SRC}/edge.pod" "${UNIT_DIR}/edge.pod"
install -m 0644 "${SRC}/edge-nginx.container" "${UNIT_DIR}/edge-nginx.container"
chmod a+x "${SRC}/acme-run.sh"
install -m 0644 "${SRC}/edge-acme.service" "${SYSTEMD_USER_DIR}/edge-acme.service"
install -m 0644 "${SRC}/edge-acme.timer" "${SYSTEMD_USER_DIR}/edge-acme.timer"

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
[[ -x "${SRC}/acme-run.sh" ]] || {
  echo "Edge acme-run.sh missing or not executable at ${SRC}/acme-run.sh" >&2
  exit 1
}

# Install lego under Edge ACME data (survives Component tree refresh).
LEGO_VERSION="v5.3.1"
LEGO_DIR="${ACME_DIR}/bin"
LEGO_BIN="${LEGO_DIR}/lego"
if [[ ! -x "${LEGO_BIN}" ]] || ! "${LEGO_BIN}" --version 2>/dev/null | grep -Fq "${LEGO_VERSION#v}"; then
  arch="$(uname -m)"
  case "${arch}" in
    x86_64 | amd64) lego_arch="amd64" ;;
    aarch64 | arm64) lego_arch="arm64" ;;
    *)
      echo "Edge ACME: unsupported architecture for lego: ${arch}" >&2
      exit 1
      ;;
  esac
  tmp="$(mktemp -d)"
  url="https://github.com/go-acme/lego/releases/download/${LEGO_VERSION}/lego_${LEGO_VERSION}_linux_${lego_arch}.tar.gz"
  echo "Edge ACME: installing lego ${LEGO_VERSION} (${lego_arch})" >&2
  curl -fsSL "${url}" -o "${tmp}/lego.tgz"
  tar -xzf "${tmp}/lego.tgz" -C "${tmp}" lego
  mkdir -p "${LEGO_DIR}"
  install -m 0755 "${tmp}/lego" "${LEGO_BIN}"
  rm -rf "${tmp}"
fi
[[ -x "${LEGO_BIN}" ]] || {
  echo "Edge ACME: lego not installed at ${LEGO_BIN}" >&2
  exit 1
}

chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}"

quadlet_user_session_reload
quadlet_user systemctl --user reset-failed edge-pod.service edge-nginx.service edge-acme.service 2>/dev/null || true
# Quadlet: edge.pod → edge-pod.service (pulls Service Network + edge-nginx).
quadlet_user systemctl --user restart edge-pod.service
quadlet_user systemctl --user --quiet is-active edge-pod.service

# On-demand ACME capability: timer armed even with an empty want-list (ADR-0015).
quadlet_user systemctl --user enable --now edge-acme.timer
quadlet_user systemctl --user --quiet is-active edge-acme.timer
# Do not block Component Setup on CA contact when the want-list is non-empty.
# restart (not start): re-ensure must re-run oneshot even if a prior oneshot is still active.
quadlet_user systemctl --user --no-block restart edge-acme.service

# Wait until Host :80 returns an HTTP status (image pull + nginx start).
for _ in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
  if [[ "${code}" =~ ^[0-9]{3}$ ]]; then
    exit 0
  fi
  sleep 2
done
echo "Edge did not become reachable on :80 in time" >&2
quadlet_user systemctl --user status edge-pod.service edge-nginx.service --no-pager >&2 || true
exit 1
