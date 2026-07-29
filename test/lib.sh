# Shared helpers for Acceptance Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from test.sh: IP and provider-observed HOST_JSON.

# PREFECT_SSH_PORT — shell twin of Terraform recreatables ssh_port (ADR-0030).
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
# shellcheck source=../lib/ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

require_do_token() {
  [[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
}

do_api_get() {
  local path="$1"
  require_do_token
  curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com${path}"
}

provider_cloud_project_json() {
  local project_name="prefect-${PREFECT_ENV}"
  do_api_get "/v2/projects?per_page=200" \
    | jq -c --arg name "${project_name}" '.projects[] | select(.name == $name)'
}

provider_cloud_project_id() {
  provider_cloud_project_json | jq -r '.id'
}

provider_host_volume_json() {
  local volume_name="prefect-${PREFECT_ENV}-web-data"
  do_api_get "/v2/volumes?name=${volume_name}&region=fra1" \
    | jq -c '.volumes[0] // empty'
}

environment_domains_path() {
  # Prefer domains.override.json when present (ADR-0021); empty when neither exists.
  if ! declare -F domains_assignment_path >/dev/null 2>&1; then
    # shellcheck source=../lib/domains.sh
    source "${REPO_ROOT}/lib/domains.sh"
  fi
  domains_assignment_path "${PREFECT_ENV}"
}

configured_domain_names() {
  local domains_path
  domains_path="$(environment_domains_path)"
  [[ -n "${domains_path}" && -f "${domains_path}" ]] || return 0
  jq -r 'keys[]' "${domains_path}"
}

require_ip() {
  [[ -n "${IP:-}" ]] || fail "fixture missing IP (run via ./test.sh)"
}

# Zero-I/O TCP probe to $IP:$1. Prints nc stdout+stderr; exit status is nc's.
# Darwin: -w alone often does not bound connect to DROP'd ports; -G is the connect timeout.
# Linux nc typically honors -w for connect and rejects unknown -G.
probe_tcp_nc() {
  local port="$1"
  local -a args=(-z -w 5 -v)
  require_ip
  if [[ "$(uname -s)" == Darwin ]]; then
    args=(-z -G 5 -w 5 -v)
  fi
  nc "${args[@]}" "${IP}" "${port}" 2>&1
}

# Allowed TCP: open or connection-refused both mean Firewall allowed the packet through.
# Timeout/drop means filtered — fail for allow-listed ports.
probe_allowed_tcp() {
  local port="$1"
  local out
  local rc
  set +e
  out="$(probe_tcp_nc "${port}")"
  rc=$?
  set -e
  if [[ ${rc} -eq 0 ]] || echo "${out}" | grep -qi "refused"; then
    pass "inbound TCP ${port} not filtered"
  else
    fail "inbound TCP ${port} appears filtered/unreachable"
  fi
}

# Denied TCP: Firewall should DROP (timeout), not allow through to a closed port (refused).
probe_denied_tcp() {
  local port="$1"
  local out
  local rc
  set +e
  out="$(probe_tcp_nc "${port}")"
  rc=$?
  set -e
  if [[ ${rc} -eq 0 ]]; then
    fail "inbound TCP ${port} unexpectedly accepted"
  elif echo "${out}" | grep -qi "refused"; then
    fail "inbound TCP ${port} reached Host (connection refused) — Firewall likely allowing it"
  else
    pass "inbound TCP ${port} filtered (denied by Firewall)"
  fi
}

# Bind verify Host-session for Acceptance (fixture IP from test.sh). Optional: VERIFY_SSH_IDENTITY.
acceptance_host_session() {
  require_ip
  host_session_bind verify "${IP}" || fail "host_session_bind verify failed for ${IP}"
}

# Run the Host-local carrier-ready gate over SSH (IHP done, floor, Prefect User, mount).
# Requires: ambient verify Host-session (acceptance_host_session), REPO_ROOT. Optional: PREFECT_USER.
wait_until_carrier_ready() {
  require_ip
  [[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"
  local script="${REPO_ROOT}/prefect/lib/wait-until-carrier-ready.sh"
  [[ -f "${script}" ]] || fail "missing ${script}"
  local user="${PREFECT_USER:-prefect}"
  if ! host_ssh "PREFECT_USER=${user} bash -s" <"${script}"; then
    fail "Host not ready for Component Setup (see Host output above)"
  fi
}

# First Domain want-list FQDN for this Environment (operator config SoT), or empty.
# Soft-skip Route attach assertions when empty (ADR-0028 fail-closed needs a want-list name).
acceptance_route_fqdn() {
  if ! declare -F domains_acme_fqdns_for >/dev/null 2>&1; then
    # shellcheck source=../lib/domains.sh
    source "${REPO_ROOT}/lib/domains.sh"
  fi
  domains_acme_fqdns_for "${PREFECT_ENV:-test}" | awk 'NF { print; exit }'
}
