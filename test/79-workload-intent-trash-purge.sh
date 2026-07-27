#!/usr/bin/env bash
# Acceptance Test: Intent trash + Purge; Domain-scoped certs survive (#54 / ADR-0024)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

stage_wl() {
  local name="$1" intent="$2"
  mkdir -p "${FIX_DIR}/${name}/quadlets"
  cat >"${FIX_DIR}/${name}/manifest.json" <<EOF
{
  "intent": "${intent}"
}
EOF
  cat >"${FIX_DIR}/${name}/quadlets/${name}.container" <<EOF
[Unit]
Description=Prefect Workload ${name}

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${name}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF
}

plant_fixture_pem() {
  local host="$1"
  ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
CERT_DIR=/var/lib/prefect/components_data/edge/certs/${host}
mkdir -p "\${CERT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "\${CERT_DIR}/privkey.pem" \
  -out "\${CERT_DIR}/fullchain.pem" \
  -days 2 -subj "/CN=${host}" >/dev/null 2>&1
chown -R prefect:prefect /var/lib/prefect/components_data/edge/certs
REMOTE
}

HOST_A="trash-a.example.test"
HOST_B="trash-b.example.test"

stage_wl trash-a run
stage_wl reclaim-b run
stage_wl keep-me stop
stage_wl purge-me run
mkdir -p "${FIX_DIR}/purge-me/routes"
cat >"${FIX_DIR}/purge-me/routes/http.conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HOST_B};
    location / { return 200 "purge-probe\n"; add_header Content-Type text/plain; }
}
EOF

want_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"

# Drop leftover Workload trees and pre-ADR-0024 invented units for these fixtures.
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<'REMOTE'
set -euo pipefail
for n in trash-a reclaim-b keep-me purge-me; do
  rm -rf "/var/lib/prefect/components_data/workloads/${n}"
  rm -f "/var/lib/prefect/components_data/edge/routes/${n}.conf"
  rm -f /var/lib/prefect/components_data/edge/routes/"${n}"--*
  rm -f "/home/prefect/.config/containers/systemd/${n}.container"
done
REMOTE

# Prior runs leave durable Host Volume state — reset these fixtures first.
for name in trash-a keep-me purge-me; do
  stage_wl "${name}" trash
  "${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${name}/manifest.json" 2>/dev/null || true
done
"${REPO_ROOT}/prefect/purge-workloads.sh" --env "${PREFECT_ENV:-test}"

stage_wl trash-a run
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/trash-a/manifest.json"
stage_wl trash-a trash
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/trash-a/manifest.json"

ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/trash-a/manifest.json" \
  || fail "Intent trash Workload data should remain until Purge"
pass "Intent trash retains Workload data until Purge"

stage_wl reclaim-b run
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/reclaim-b/manifest.json"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/workloads/reclaim-b/manifest.json" \
  || fail "second Intent run Workload should Setup"
pass "Intent run Workload Setup does not depend on hostname claims"

stage_wl keep-me stop
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/keep-me/manifest.json"
stage_wl purge-me run
mkdir -p "${FIX_DIR}/purge-me/routes"
cat >"${FIX_DIR}/purge-me/routes/http.conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HOST_B};
    location / { return 200 "purge-probe\n"; add_header Content-Type text/plain; }
}
EOF
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/purge-me/manifest.json"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/edge/routes/purge-me--http.conf" \
  || fail "Intent run should install operator Route purge-me--http.conf"
plant_fixture_pem "${HOST_B}"
plant_fixture_pem "${HOST_A}"
stage_wl purge-me trash
mkdir -p "${FIX_DIR}/purge-me/routes"
cat >"${FIX_DIR}/purge-me/routes/http.conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HOST_B};
    location / { return 200 "purge-probe\n"; add_header Content-Type text/plain; }
}
EOF
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/purge-me/manifest.json"
# Intent trash Setup already uninstalls Routes; plant a leftover so Purge must clear it.
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
printf '%s\n' 'leftover-route' > /var/lib/prefect/components_data/edge/routes/purge-me--http.conf
chown prefect:prefect /var/lib/prefect/components_data/edge/routes/purge-me--http.conf
REMOTE
"${REPO_ROOT}/prefect/purge-workloads.sh" --env "${PREFECT_ENV:-test}"

ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/purge-me" \
  || fail "Purge should remove Intent trash purge-me data"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/trash-a" \
  || fail "Purge should remove Intent trash trash-a data"
purge_routes="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "ls /var/lib/prefect/components_data/edge/routes/purge-me.conf /var/lib/prefect/components_data/edge/routes/purge-me--* 2>/dev/null || true")"
[[ -z "${purge_routes}" ]] || fail "Purge should remove installed Routes for trash Workloads (got: ${purge_routes})"
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e /home/prefect/.config/containers/systemd/purge-me.container"; then
  fail "Purge should remove related Quadlet unit for purge-me"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/keep-me/manifest.json" \
  || fail "Purge must not touch Intent stop keep-me"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/reclaim-b/manifest.json" \
  || fail "Purge must not touch Intent run reclaim-b"
# Domain-scoped certificate material survives Purge (ADR-0022 / #54).
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/edge/certs/${HOST_B}/fullchain.pem \
   && test -f /var/lib/prefect/components_data/edge/certs/${HOST_B}/privkey.pem" \
  || fail "Purge must keep Domain-scoped certificates for ${HOST_B}"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/edge/certs/${HOST_A}/fullchain.pem \
   && test -f /var/lib/prefect/components_data/edge/certs/${HOST_A}/privkey.pem" \
  || fail "Purge must keep Domain-scoped certificates for ${HOST_A}"
want_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"
[[ "${want_after}" == "${want_before}" ]] \
  || fail "Purge must not rewrite ACME want-list"
pass "Purge removes trash Workloads/Routes/units; keeps Domain-scoped certs; leaves want-list unchanged"
