#!/usr/bin/env bash
# Acceptance Test: HTTPS Route shell + HTTP→HTTPS redirect when fixture PEM exists
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="tls.example.test"
FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

cat >"${FIX_DIR}/manifest.json" <<EOF
{
  "name": "tlsprobe",
  "state": "running",
  "public_hostnames": ["${HOST}"],
  "upstream": "tlsprobe:8080"
}
EOF

"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

# Ensure no leftover fixture PEM from a prior run (Host Volume is durable).
ssh "${SSH_OPTS[@]}" "root@${IP}" "rm -rf /var/lib/prefect/components_data/edge/certs/${HOST}"
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

# Without a certificate, no HTTPS shell for this name (TLS handshake must not succeed for SNI).
set +e
tls_before="$(curl -skS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
  --resolve "${HOST}:443:${IP}" "https://${HOST}/" 2>/tmp/tls-before.err)"
tls_before_rc=$?
set -e
if [[ ${tls_before_rc} -eq 0 && "${tls_before}" =~ ^[0-9]{3}$ ]]; then
  fail "HTTPS shell must not be enabled before certificate exists (got HTTP ${tls_before})"
fi
pass "HTTPS Route shell absent before certificate exists"

# Install fixture PEM on Host Volume (not live Let's Encrypt).
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

# Re-apply Workload Setup so Routes pick up the cert (Setup does not wait on ACME).
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

tls_code="$(curl -skS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  --resolve "${HOST}:443:${IP}" "https://${HOST}/")"
[[ "${tls_code}" =~ ^[0-9]{3}$ ]] || fail "TLS to ${HOST} failed (code='${tls_code}')"
pass "TLS to Public Hostname succeeds with fixture PEM (HTTP ${tls_code})"

# :80 redirects to HTTPS for cert-ready names
redir="$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --connect-timeout 10 --max-time 15 \
  -H "Host: ${HOST}" "http://${IP}/")"
redir_code="${redir%% *}"
redir_url="${redir#* }"
[[ "${redir_code}" == "301" || "${redir_code}" == "302" ]] \
  || fail "expected redirect on :80 for cert-ready name, got '${redir}'"
[[ "${redir_url}" == https://${HOST}/ || "${redir_url}" == https://${HOST}/* ]] \
  || echo "${redir_url}" | grep -q "^https://${HOST}" \
  || fail "redirect target expected https://${HOST}/..., got '${redir_url}'"
pass ":80 redirects to HTTPS for cert-ready Public Hostname"

# ACME challenge path remains on :80 (no redirect)
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

# No cleartext Workload proxy on :80
clear_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  -H "Host: ${HOST}" "http://${IP}/" || true)"
[[ "${clear_code}" == "301" || "${clear_code}" == "302" ]] \
  || fail "cleartext / should redirect, not proxy (got HTTP ${clear_code})"
pass "No cleartext Workload proxy on :80"
