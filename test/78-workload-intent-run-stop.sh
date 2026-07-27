#!/usr/bin/env bash
# Acceptance Test: Intent run with authored Quadlet + operator Route; Intent stop (#57 / ADR-0024)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="app.example.test"
WL=app
FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

mkdir -p "${FIX_DIR}/${WL}/routes" "${FIX_DIR}/${WL}/quadlets"
write_manifest() {
  local intent="$1"
  cat >"${FIX_DIR}/${WL}/manifest.json" <<EOF
{
  "intent": "${intent}"
}
EOF
}
cat >"${FIX_DIR}/${WL}/routes/https.conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HOST};
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/acme;
        default_type text/plain;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${HOST};
    ssl_certificate     /etc/nginx/certs/${HOST}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/${HOST}/privkey.pem;
    location / {
        proxy_pass http://${WL}:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
cat >"${FIX_DIR}/${WL}/quadlets/${WL}.container" <<EOF
[Unit]
Description=Prefect Workload ${WL}

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${WL}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF

want_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "rm -rf /var/lib/prefect/components_data/edge/certs/${HOST} \
          /var/lib/prefect/components_data/edge/routes/${WL}.conf \
          /var/lib/prefect/components_data/edge/routes/${WL}--* \
          /var/lib/prefect/components_data/workloads/${WL}; \
   rm -f /home/prefect/.config/containers/systemd/${WL}.container"

# PEMs before operator HTTPS Route (nginx requires certificate files to exist).
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
CERT_DIR=/var/lib/prefect/components_data/edge/certs/${HOST}
mkdir -p "\${CERT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "\${CERT_DIR}/privkey.pem" \
  -out "\${CERT_DIR}/fullchain.pem" \
  -days 2 -subj "/CN=${HOST}" >/dev/null 2>&1
chown -R prefect:prefect /var/lib/prefect/components_data/edge/certs
REMOTE

write_manifest run
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${WL}/manifest.json"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/workloads/${WL}/quadlets/${WL}.container" \
  || fail "Intent run should store authored Quadlet SoT"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /home/prefect/.config/containers/systemd/${WL}.container" \
  || fail "Intent run should install authored Quadlet unit file"

ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
UID_NUM="\$(id -u prefect)"
export XDG_RUNTIME_DIR="/run/user/\${UID_NUM}"
systemctl start "user@\${UID_NUM}.service"
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" PREFECT_ACME_ISSUE=0 \
  /var/lib/prefect/components/edge/acme-run.sh
REMOTE

body=""
for _ in $(seq 1 30); do
  body="$(curl -skS --connect-timeout 5 --max-time 10 \
    --resolve "${HOST}:443:${IP}" "https://${HOST}/" 2>/dev/null || true)"
  if echo "${body}" | grep -qi 'nginx\|welcome\|html'; then
    break
  fi
  sleep 2
done
echo "${body}" | grep -qi 'nginx\|welcome\|html' \
  || fail "Intent run+cert: expected proxied Workload body over HTTPS, got '${body:0:200}'"
pass "Intent run + cert: Edge proxies to authored Quadlet Workload over HTTPS"

write_manifest stop
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${WL}/manifest.json"

stop_routes="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "ls /var/lib/prefect/components_data/edge/routes/${WL}.conf /var/lib/prefect/components_data/edge/routes/${WL}--* 2>/dev/null || true")"
[[ -z "${stop_routes}" ]] || fail "Intent stop must remove Workload installed Routes (got: ${stop_routes})"
pass "Intent stop removes Workload installed Routes from Edge"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /home/prefect/.config/containers/systemd/${WL}.container" \
  || fail "Intent stop should retain unit file until Purge"
active="$(ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
UID_NUM=\$(id -u prefect)
export XDG_RUNTIME_DIR=/run/user/\${UID_NUM}
if runuser -u prefect -- env XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR \
  systemctl --user --quiet is-active ${WL}.service 2>/dev/null; then
  echo active
else
  echo inactive
fi
REMOTE
)"
[[ "${active}" == "inactive" ]] || fail "Intent stop: Workload Quadlet should not be active"
pass "Intent stop: Workload Quadlets are inactive; unit file retained"

want_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"
[[ "${want_after}" == "${want_before}" ]] \
  || fail "Intent stop must not rewrite ACME want-list"
pass "Intent stop leaves Domain ACME want-list unchanged"

# Edge default miss — not a Prefect-managed 503 shell (ADR-0022).
code=""
for _ in $(seq 1 30); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
    -H "Host: ${HOST}" "http://${IP}/" 2>/dev/null || true)"
  [[ "${code}" == "404" ]] && break
  sleep 1
done
[[ "${code}" == "404" ]] || fail "Intent stop: expected Edge default miss HTTP 404 on :80 (not 503), got '${code}'"
pass "Intent stop: previously routed name misses to Edge default (HTTP 404 on :80)"
