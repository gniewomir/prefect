# Shared helpers for Lifecycle Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from lifecycle-test.sh: REPO_ROOT. Optional: VERIFY_SSH_IDENTITY.
# Reuses Acceptance Test helpers for pass/fail / SSH / carrier-ready.

# shellcheck source=../test/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../test/lib.sh"

STACK_DIR="${REPO_ROOT}/terraform"

# Provider-visible Durable identifiers (not State addresses).
DURABLE_VOLUME_NAME="prefect-web-data"
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
