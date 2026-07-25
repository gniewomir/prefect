#!/usr/bin/env bash
# Acceptance Test: Workload Setup applies Manifest — Route shell, ACME wants, uniqueness
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

cat >"${FIX_DIR}/alpha.json" <<'EOF'
{
  "name": "alpha",
  "intent": "run",
  "public_hostnames": ["alpha.example.test"],
  "upstream": "alpha:8080"
}
EOF

cat >"${FIX_DIR}/beta.json" <<'EOF'
{
  "name": "beta",
  "intent": "run",
  "public_hostnames": ["alpha.example.test"],
  "upstream": "beta:8080"
}
EOF

mkdir -p "${FIX_DIR}/gamma" "${FIX_DIR}/gamma-bad"
cat >"${FIX_DIR}/gamma/manifest.json" <<'EOF'
{
  "name": "gamma",
  "intent": "run",
  "public_hostnames": ["gamma.example.test"],
  "upstream": "gamma:8080",
  "interior": "interior.conf"
}
EOF
cat >"${FIX_DIR}/gamma/interior.conf" <<'EOF'
location / {
    proxy_pass http://gamma:8080;
}
EOF

cat >"${FIX_DIR}/gamma-bad/manifest.json" <<'EOF'
{
  "name": "gamma-bad",
  "intent": "run",
  "public_hostnames": ["gamma-bad.example.test"],
  "upstream": "gamma-bad:8080",
  "interior": "interior.conf"
}
EOF
cat >"${FIX_DIR}/gamma-bad/interior.conf" <<'EOF'
server_name stolen.example.test;
location / {
    proxy_pass http://gamma-bad:8080;
}
EOF

"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/alpha.json"

route="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/routes/alpha.conf")"
echo "${route}" | grep -q 'server_name alpha.example.test' \
  || fail "Route shell missing Public Hostname server_name"
echo "${route}" | grep -q 'listen 80' \
  || fail "Route shell missing listen 80"
claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/alpha.example.test")"
[[ "${claim}" == "alpha" ]] || fail "claim expected alpha, got '${claim}'"
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx 'alpha.example.test' \
  || fail "ACME want-list missing alpha.example.test (got: ${want})"
pass "Workload Setup projects Route shell, claim, and ACME want-list"

set +e
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/beta.json" >/tmp/beta-setup.out 2>&1
beta_rc=$?
set -e
if [[ ${beta_rc} -eq 0 ]]; then
  fail "expected uniqueness failure when beta claims alpha.example.test"
fi
grep -qi 'already claimed\|conflict\|unique' /tmp/beta-setup.out \
  || fail "uniqueness failure did not mention claim conflict (output: $(cat /tmp/beta-setup.out))"
pass "Workload Setup fails when Public Hostname is already claimed"

"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/gamma/manifest.json"
gamma_route="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/routes/gamma.conf")"
echo "${gamma_route}" | grep -q 'server_name gamma.example.test' \
  || fail "gamma Route shell missing Public Hostname"
echo "${gamma_route}" | grep -q 'return 404' \
  || fail "HTTP Route shell must not cleartext-proxy (expected 404)"
! echo "${gamma_route}" | grep -q 'proxy_pass' \
  || fail "HTTP Route shell must not include interior proxy_pass (ADR-0013)"
interior_stored="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/workloads/gamma/interior.conf")"
echo "${interior_stored}" | grep -q 'proxy_pass http://gamma:8080' \
  || fail "optional interior not stored for later HTTPS Route use"
pass "Workload Setup accepts optional Route interior (proxy body only; stored, not cleartext)"

set +e
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/gamma-bad/manifest.json" >/tmp/gamma-bad.out 2>&1
bad_rc=$?
set -e
if [[ ${bad_rc} -eq 0 ]]; then
  fail "expected failure when interior declares server_name"
fi
pass "Workload Setup rejects interior that declares Public Hostnames"

# Setup must not block on issuance — alpha applied with no cert / no live CA
code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
  -H 'Host: alpha.example.test' "http://${IP}/" || true)"
[[ "${code}" == "404" ]] || fail "named Host without cert: expected HTTP 404, got '${code}'"
pass "Workload Setup succeeds without waiting for certificate issuance"
