#!/usr/bin/env bash
# Acceptance Test: Intent run with operator Route; Intent stop drops claim/want-list (#52/#53 seam)
# Full stop→404 / uninstall assertions are owned by #53; here stop must not leave ACME renewing.
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

mkdir -p "${FIX_DIR}/routes"
write_manifest() {
  local intent="$1"
  cat >"${FIX_DIR}/manifest.json" <<EOF
{
  "name": "${WL}",
  "intent": "${intent}",
  "public_hostnames": ["${HOST}"],
  "upstream": "${WL}:80"
}
EOF
}
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
        proxy_pass http://${WL}:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "rm -rf /var/lib/prefect/components_data/edge/certs/${HOST} \
          /var/lib/prefect/components_data/edge/routes/${WL}.conf \
          /var/lib/prefect/components_data/edge/routes/${WL}--* \
          /var/lib/prefect/components_data/workloads/${WL} \
          /var/lib/prefect/components_data/edge/claims/${HOST}"

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
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/manifest.json"

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
pass "Intent run + cert: Edge proxies to Workload over HTTPS via operator Route"

write_manifest stop
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/manifest.json"

if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/edge/claims/${HOST}"; then
  fail "Intent stop must release Public Hostname claim (unique among Intent run only)"
fi
pass "Intent stop releases Public Hostname claim"

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
pass "Intent stop: Workload Quadlets are inactive"

# #52: stop must not keep renewing; Route uninstall / :80 404 is #53 (may already be true if Setup reconciles)
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
if echo "${want}" | grep -qx "${HOST}"; then
  fail "Intent stop must not renew certificates (hostname still in ACME want-list)"
fi
pass "Intent stop does not renew certificates (absent from ACME want-list)"
