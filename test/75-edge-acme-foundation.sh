#!/usr/bin/env bash
# Acceptance Test: Edge ACME foundation after ensure-components (no live CA / no Public Hostname)
# Covers: :443 published, HTTP-01 webroot on :80, empty want-list oneshot + user timer, empty Edge 404.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

USER_NAME="${PREFECT_USER:-prefect}"
DATA_ROOT=/var/lib/prefect/components_data/edge
ACME_WWW="${DATA_ROOT}/acme-www"
WANT_LIST="${DATA_ROOT}/acme/want-list"
TOKEN="prefect-acme-foundation-probe"
TOKEN_PATH="${ACME_WWW}/.well-known/acme-challenge/${TOKEN}"

# Host :443 is published by the Edge (listener present — TLS shells come later).
if ! ssh "${SSH_OPTS[@]}" "root@${IP}" "ss -ltn | grep -qE ':443[[:space:]]'"; then
  fail "Host :443 is not listening (Edge should PublishPort 443)"
fi
pass "Edge publishes Host :443"

# Empty Edge :80 still 404 on /
code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 "http://${IP}/" || true)"
if [[ "${code}" != "404" ]]; then
  fail "empty Edge on Host :80: expected HTTP 404, got '${code}'"
fi
pass "empty Edge still returns HTTP 404 on /"

# :80 serves the ACME HTTP-01 webroot path
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
mkdir -p "$(dirname "${TOKEN_PATH}")"
printf '%s\n' '${TOKEN}' >"${TOKEN_PATH}"
chown -R ${USER_NAME}:${USER_NAME} "${ACME_WWW}"
REMOTE

body="$(curl -sS --connect-timeout 10 --max-time 15 "http://${IP}/.well-known/acme-challenge/${TOKEN}" || true)"
if [[ "${body}" != "${TOKEN}" ]]; then
  fail "ACME webroot on :80: expected body '${TOKEN}', got '${body}'"
fi
pass "Edge serves ACME HTTP-01 webroot on :80"

# Want-list exists and is empty (no Public Hostnames yet)
want_state="$(ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
if [[ ! -f "${WANT_LIST}" ]]; then
  echo missing
  exit 0
fi
if grep -q '[^[:space:]]' "${WANT_LIST}"; then
  echo nonempty
else
  echo empty
fi
REMOTE
)"
if [[ "${want_state}" != "empty" ]]; then
  fail "ACME want-list expected empty file, got '${want_state}'"
fi
pass "ACME want-list is empty"

# Oneshot + timer installed under Prefect User; oneshot succeeds with empty want-list
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
UID_NUM="\$(id -u ${USER_NAME})"
export XDG_RUNTIME_DIR="/run/user/\${UID_NUM}"
systemctl start "user@\${UID_NUM}.service"
runuser -u ${USER_NAME} -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \
  systemctl --user --quiet is-active edge-acme.timer
runuser -u ${USER_NAME} -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \
  systemctl --user start edge-acme.service
REMOTE
pass "Edge ACME timer active; oneshot succeeds with empty want-list"
