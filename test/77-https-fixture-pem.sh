#!/usr/bin/env bash
# Acceptance Test: operator Route + fixture PEM — HTTPS and :80 redirect (#52)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="tls.example.test"
WL="tlsprobe"
FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

mkdir -p "${FIX_DIR}/routes"
cat >"${FIX_DIR}/manifest.json" <<EOF
{
  "name": "${WL}",
  "intent": "run",
  "public_hostnames": ["${HOST}"],
  "upstream": "${WL}:8080"
}
EOF
# Operator-authored HTTPS Route (Prefect does not generate shells).
cat >"${FIX_DIR}/routes/https.conf" <<EOF
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
        return 200 'tlsprobe-ok';
        add_header Content-Type text/plain;
    }
}
EOF

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "rm -rf /var/lib/prefect/components_data/edge/certs/${HOST} \
          /var/lib/prefect/components_data/edge/routes/${WL}.conf \
          /var/lib/prefect/components_data/edge/routes/${WL}--* \
          /var/lib/prefect/components_data/workloads/${WL}"

# Plant PEMs before installing an operator Route that references them (nginx requires files present).
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

"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/manifest.json"

installed="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/routes/${WL}--https.conf")"
echo "${installed}" | grep -q 'listen 443 ssl' \
  || fail "operator Route must include HTTPS server (authored)"
pass "Operator Route installed with HTTPS server block as authored"

# Reload Edge so TLS sockets are live (Setup may race ACME; force reload).
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
UID_NUM="\$(id -u prefect)"
export XDG_RUNTIME_DIR="/run/user/\${UID_NUM}"
systemctl start "user@\${UID_NUM}.service"
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \
  systemctl --user stop edge-acme.service 2>/dev/null || true
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" PREFECT_ACME_ISSUE=0 \
  /var/lib/prefect/components/edge/acme-run.sh
REMOTE

tls_code=""
for _ in $(seq 1 30); do
  tls_code="$(curl -skS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
    --resolve "${HOST}:443:${IP}" "https://${HOST}/" 2>/dev/null || true)"
  # curl prints 000 when the Edge is mid-reload — keep retrying until a real status.
  [[ "${tls_code}" =~ ^[1-5][0-9]{2}$ ]] && break
  sleep 1
done
[[ "${tls_code}" =~ ^[1-5][0-9]{2}$ ]] || fail "TLS to ${HOST} failed (code='${tls_code}')"
pass "TLS to Public Hostname succeeds with fixture PEM (HTTP ${tls_code})"

redir="$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --connect-timeout 10 --max-time 15 \
  -H "Host: ${HOST}" "http://${IP}/")"
redir_code="${redir%% *}"
redir_url="${redir#* }"
[[ "${redir_code}" == "301" || "${redir_code}" == "302" ]] \
  || fail "expected redirect on :80 for cert-ready name, got '${redir}'"
echo "${redir_url}" | grep -q "^https://${HOST}" \
  || fail "redirect target expected https://${HOST}/..., got '${redir_url}'"
pass ":80 redirects to HTTPS for cert-ready Public Hostname"

TOKEN="tls-acme-probe"
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
TOKEN_PATH=/var/lib/prefect/components_data/edge/acme-www/.well-known/acme-challenge/${TOKEN}
mkdir -p "\$(dirname "\${TOKEN_PATH}")"
printf '%s\n' '${TOKEN}' >"\${TOKEN_PATH}"
chown -R prefect:prefect /var/lib/prefect/components_data/edge/acme-www
REMOTE
acme_body="$(curl -sS --connect-timeout 10 --max-time 15 \
  -H "Host: ${HOST}" "http://${IP}/.well-known/acme-challenge/${TOKEN}")"
[[ "${acme_body}" == "${TOKEN}" ]] || fail "ACME path on :80 broken after redirect shell (got '${acme_body}')"
pass "ACME challenge path remains reachable on :80"

clear_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  -H "Host: ${HOST}" "http://${IP}/" || true)"
[[ "${clear_code}" == "301" || "${clear_code}" == "302" ]] \
  || fail "cleartext / should redirect, not proxy (got HTTP ${clear_code})"
pass "No cleartext Workload proxy on :80"
