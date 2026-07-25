#!/usr/bin/env bash
# Acceptance Test: Intent run proxies over HTTPS; Intent stop returns 503 (fixture PEM)
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

ssh "${SSH_OPTS[@]}" "root@${IP}" "rm -rf /var/lib/prefect/components_data/edge/certs/${HOST}"
write_manifest run
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

# Fixture PEM then re-apply so HTTPS shell + proxy are live
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
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

# Wait for Workload + Edge
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
pass "Intent run + cert: Edge proxies to Workload over HTTPS"

# Intent stop: claim retained, Quadlet down, HTTPS 503, not in want-list
write_manifest stop
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/${HOST}")"
[[ "${claim}" == "${WL}" ]] || fail "Intent stop should retain claim (got '${claim}')"
pass "Intent stop retains Public Hostname claim"

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

code="$(curl -skS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  --resolve "${HOST}:443:${IP}" "https://${HOST}/")"
[[ "${code}" == "503" ]] || fail "Intent stop+cert: expected HTTPS 503, got '${code}'"
pass "Intent stop + usable cert: HTTPS returns 503"

want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
if echo "${want}" | grep -qx "${HOST}"; then
  fail "Intent stop must not renew certificates (hostname still in ACME want-list)"
fi
pass "Intent stop does not renew certificates (absent from ACME want-list)"
