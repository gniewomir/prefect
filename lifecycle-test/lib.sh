# Shared helpers for Lifecycle Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from lifecycle-test.sh: REPO_ROOT. Optional: VERIFY_SSH_IDENTITY.
# Reuses Acceptance Test helpers for pass/fail / SSH / carrier-ready.
# Resolve siblings via REPO_ROOT — not BASH_SOURCE — so sourcing from zsh (operator
# shells) works the same as bash (Lifecycle cases run under bash).

[[ -n "${REPO_ROOT:-}" ]] || {
  echo "FAIL: fixture missing REPO_ROOT (run via ./lifecycle-test.sh)" >&2
  return 1 2>/dev/null || exit 1
}

# shellcheck source=../test/lib.sh
source "${REPO_ROOT}/test/lib.sh"
# shellcheck source=../lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"

STACK_DIR="${REPO_ROOT}/terraform"

# Provider-visible Durable identifiers (not State addresses). Derived from PREFECT_ENV.
DURABLE_VOLUME_NAME="$(environment_volume_name_for "${PREFECT_ENV:-test}")"
DURABLE_VOLUME_REGION="fra1"

require_do_token() {
  [[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
}

# GET DigitalOcean API path; prints body on stdout. Uses DIGITALOCEAN_TOKEN.
do_api_get() {
  local path="$1"
  require_do_token
  curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com${path}"
}

# Assert Reserved IP still exists at the provider (survives Park).
assert_reserved_ip_present() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_reserved_ip_present: empty IP"
  local body
  body="$(do_api_get "/v2/reserved_ips/${ip}")" \
    || fail "Reserved IP ${ip} not found at provider"
  echo "${body}" | jq -e --arg ip "${ip}" '.reserved_ip.ip == $ip' >/dev/null \
    || fail "Reserved IP provider payload mismatch for ${ip}"
  pass "Reserved IP ${ip} present at provider"
}

# Assert Host Volume still exists at the provider (survives Park).
assert_volume_present() {
  local name="${1:-${DURABLE_VOLUME_NAME}}"
  local region="${2:-${DURABLE_VOLUME_REGION}}"
  local body
  body="$(do_api_get "/v2/volumes?name=${name}&region=${region}")" \
    || fail "volume list request failed for ${name}"
  echo "${body}" | jq -e '.volumes | length >= 1' >/dev/null \
    || fail "Host Volume ${name} not found at provider in ${region}"
  pass "Host Volume ${name} present at provider"
}

# Assert Reserved IP is gone at the provider (after Teardown).
assert_reserved_ip_absent() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_reserved_ip_absent: empty IP"
  require_do_token
  local http_code
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/reserved_ips/${ip}")" \
    || fail "Reserved IP lookup request failed for ${ip}"
  [[ "${http_code}" == "404" ]] \
    || fail "Reserved IP ${ip} still present at provider (HTTP ${http_code})"
  pass "Reserved IP ${ip} gone from provider"
}

# Assert Host Volume is gone at the provider (after Teardown).
assert_volume_absent() {
  local name="${1:-${DURABLE_VOLUME_NAME}}"
  local region="${2:-${DURABLE_VOLUME_REGION}}"
  local body
  body="$(do_api_get "/v2/volumes?name=${name}&region=${region}")" \
    || fail "volume list request failed for ${name}"
  echo "${body}" | jq -e '.volumes | length == 0' >/dev/null \
    || fail "Host Volume ${name} still present at provider in ${region}"
  pass "Host Volume ${name} gone from provider"
}

# Apex FQDNs for Domain Durables currently in State (empty if none configured).
stack_domain_names() {
  (cd "${STACK_DIR}" && terraform state list 2>/dev/null) \
    | sed -n 's/^digitalocean_domain\.this\["\(.*\)"]$/\1/p'
}

# Assert each Stack Domain zone still exists and has A → Reserved IP (survives Park).
# No-op pass when zero Domains are in State (operator has not configured Domains).
assert_domains_present() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_domains_present: empty Reserved IP"
  local zones zone body
  zones="$(stack_domain_names)"
  if [[ -z "${zones}" ]]; then
    pass "Domain Durables not in State — skip Domain present asserts"
    return 0
  fi
  while IFS= read -r zone; do
    [[ -z "${zone}" ]] && continue
    do_api_get "/v2/domains/${zone}" >/dev/null \
      || fail "Domain ${zone} not found at provider"
    body="$(do_api_get "/v2/domains/${zone}/records")" \
      || fail "Domain ${zone} records list failed"
    echo "${body}" | jq -e --arg ip "${ip}" \
      '[.domain_records[] | select(.type == "A" and .data == $ip)] | length >= 1' >/dev/null \
      || fail "Domain ${zone} has no A record → Reserved IP ${ip} at provider"
    pass "Domain ${zone} present with A → ${ip}"
  done <<< "${zones}"
}

# Assert each listed Domain zone is gone at the provider (after Teardown).
assert_domains_absent() {
  local zones="$1"
  if [[ -z "${zones}" ]]; then
    pass "Domain Durables were not configured — skip Domain absent asserts"
    return 0
  fi
  require_do_token
  local zone http_code
  while IFS= read -r zone; do
    [[ -z "${zone}" ]] && continue
    http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.digitalocean.com/v2/domains/${zone}")" \
      || fail "Domain lookup request failed for ${zone}"
    [[ "${http_code}" == "404" ]] \
      || fail "Domain ${zone} still present at provider (HTTP ${http_code})"
    pass "Domain ${zone} gone from provider"
  done <<< "${zones}"
}

# Assert Stack State has no managed addresses (Teardown leftover: empty).
assert_stack_empty() {
  local addrs
  addrs="$(cd "${STACK_DIR}" && terraform state list)"
  [[ -z "${addrs}" ]] || fail "Stack State not empty after Teardown: ${addrs}"
  pass "Stack State empty"
}

stack_reserved_ip() {
  (cd "${STACK_DIR}" && terraform output -raw reserved_ip)
}

# Poll until pubkey SSH to root@$IP works (Host create / boot lag after Apply).
# Optional: SSH_READY_TIMEOUT_SECONDS (default 300).
wait_until_ssh_reachable() {
  require_ip
  acceptance_ssh_opts
  local timeout="${SSH_READY_TIMEOUT_SECONDS:-300}"
  local deadline=$((SECONDS + timeout))
  echo "Waiting for SSH at ${IP} (up to ${timeout}s) ..."
  while ((SECONDS < deadline)); do
    if ssh "${SSH_OPTS[@]}" "root@${IP}" "true" >/dev/null 2>&1; then
      pass "SSH reachable at ${IP}"
      return 0
    fi
    sleep 5
  done
  fail "SSH not reachable at ${IP} within ${timeout}s"
}

# Poll until Host Volume is mounted at /var/lib/prefect (does not wait for full IHP).
# Optional: VOLUME_MOUNT_TIMEOUT_SECONDS (default 300).
wait_until_volume_mounted() {
  require_ip
  acceptance_ssh_opts
  local timeout="${VOLUME_MOUNT_TIMEOUT_SECONDS:-300}"
  local deadline=$((SECONDS + timeout))
  echo "Waiting for Host Volume mount at ${IP}:/var/lib/prefect (up to ${timeout}s) ..."
  while ((SECONDS < deadline)); do
    if ssh "${SSH_OPTS[@]}" "root@${IP}" "findmnt --mountpoint /var/lib/prefect" >/dev/null 2>&1; then
      pass "Host Volume mounted at /var/lib/prefect"
      return 0
    fi
    sleep 5
  done
  fail "Host Volume not mounted at /var/lib/prefect within ${timeout}s"
}
