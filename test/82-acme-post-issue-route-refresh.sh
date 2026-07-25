#!/usr/bin/env bash
# Acceptance Test: after PEMs appear, Edge ACME refreshes Routes + reloads Edge
# so HTTPS is live without a second Workload Setup (issue #33).
# Uses fixture PEMs + PREFECT_ACME_ISSUE=0 (no live CA / public domain).
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="acme-refresh.example.test"
WL="acme-refresh"
FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

cat >"${FIX_DIR}/manifest.json" <<EOF
{
  "name": "${WL}",
  "intent": "run",
  "public_hostnames": ["${HOST}"],
  "upstream": "${WL}:80"
}
EOF

# Clean durable leftovers from prior runs.
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "rm -rf /var/lib/prefect/components_data/edge/certs/${HOST} \
          /var/lib/prefect/components_data/edge/routes/${WL}.conf \
          /var/lib/prefect/components_data/workloads/${WL}"

"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

route_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/routes/${WL}.conf")"
echo "${route_before}" | grep -q 'listen 443' \
  && fail "HTTPS shell must be absent before certificate exists" || true
pass "HTTPS Route shell absent before certificate / refresh"

# Plant fixture PEM (simulates successful ACME write onto Host Volume).
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

# Do NOT re-run Workload Setup. Stop any in-flight ACME from Setup, then refresh Routes.
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
UID_NUM="\$(id -u prefect)"
export XDG_RUNTIME_DIR="/run/user/\${UID_NUM}"
systemctl start "user@\${UID_NUM}.service"
# Avoid racing a background oneshot still contacting the CA for fixture names.
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \
  systemctl --user stop edge-acme.service 2>/dev/null || true
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" PREFECT_ACME_ISSUE=0 \
  /var/lib/prefect/components/edge/acme-run.sh
REMOTE

route_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/routes/${WL}.conf")"
echo "${route_after}" | grep -q 'listen 443 ssl' \
  || fail "after ACME refresh, Route must enable HTTPS shell (got no listen 443 ssl)"
pass "ACME oneshot refreshes Route HTTPS shell without Workload Setup"

tls_code="$(curl -skS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  --resolve "${HOST}:443:${IP}" "https://${HOST}/")"
[[ "${tls_code}" =~ ^[0-9]{3}$ ]] || fail "TLS to ${HOST} failed after ACME refresh (code='${tls_code}')"
pass "HTTPS live after ACME Route refresh without re-Setup (HTTP ${tls_code})"

redir_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  -H "Host: ${HOST}" "http://${IP}/")"
[[ "${redir_code}" == "301" || "${redir_code}" == "302" ]] \
  || fail "expected :80 redirect after refresh, got HTTP ${redir_code}"
pass ":80 redirects to HTTPS after ACME Route refresh"
