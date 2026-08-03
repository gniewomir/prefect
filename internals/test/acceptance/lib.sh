# Shared helpers for Acceptance Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from ./test.sh acceptance: IP and provider-observed HOST_JSON.

# SSH port twin of Terraform recreatables ssh_port (ADR-0030) — see internals/lib/ssh.sh.
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi
# shellcheck source=../../lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"
# shellcheck source=../../lib/ihp.sh
source "${REPO_ROOT}/internals/lib/ihp.sh"

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
  local project_name="propraetor-${PLATFORM_ENV}"
  do_api_get "/v2/projects?per_page=200" \
    | jq -c --arg name "${project_name}" '.projects[] | select(.name == $name)'
}

provider_cloud_project_id() {
  provider_cloud_project_json | jq -r '.id'
}

provider_host_volume_json() {
  local volume_name="propraetor-${PLATFORM_ENV}-web-data"
  do_api_get "/v2/volumes?name=${volume_name}&region=fra1" \
    | jq -c '.volumes[0] // empty'
}

environment_domains_path() {
  # Prefer domains.override.json when present (ADR-0021); empty when neither exists.
  if ! declare -F domains_assignment_path >/dev/null 2>&1; then
    # shellcheck source=../../lib/domains/domains.sh
    source "${REPO_ROOT}/internals/lib/domains/domains.sh"
  fi
  domains_assignment_path "${PLATFORM_ENV}"
}

configured_domain_names() {
  local domains_path
  domains_path="$(environment_domains_path)"
  [[ -n "${domains_path}" && -f "${domains_path}" ]] || return 0
  jq -r 'keys[]' "${domains_path}"
}

require_ip() {
  [[ -n "${IP:-}" ]] || fail "fixture missing IP (run via ./test.sh acceptance)"
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

# Bind verify Host-session for Acceptance (fixture IP from ./test.sh acceptance).
# Identity: PROPRAETOR_PRIVATE_KEY_PATH (Operator Configuration).
acceptance_host_session() {
  require_ip
  host_session_bind verify "${IP}" || fail "host_session_bind verify failed for ${IP}"
}

# Run the Host-local ihp-done gate over SSH (retries across ADR-0030 reboot).
# Requires: ambient verify Host-session (acceptance_host_session), REPO_ROOT. Optional: PLATFORM_USER.
wait_until_ihp_done() {
  require_ip
  [[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh acceptance)"
  local script="${REPO_ROOT}/internals/host-scripts/wait-until-ihp-done.sh"
  local user="${PLATFORM_USER:-platform}"
  if ! host_wait_until_ihp_done "${script}" "${user}"; then
    fail "Host not ready for Component Setup (see Host output above)"
  fi
}

# First Domain want-list FQDN for this Environment (operator config SoT), or empty.
# Soft-skip Route attach assertions when empty (ADR-0028 fail-closed needs a want-list name).
acceptance_route_fqdn() {
  if ! declare -F domains_acme_fqdns_for >/dev/null 2>&1; then
    # shellcheck source=../../lib/domains/domains.sh
    source "${REPO_ROOT}/internals/lib/domains/domains.sh"
  fi
  domains_acme_fqdns_for "${PLATFORM_ENV:-test}" | awk 'NF { print; exit }'
}

# Ephemeral Workload trees under environments/<slug>/ (ADR-0033).
acceptance_env_dir() {
  printf '%s/environments/%s\n' "${REPO_ROOT}" "${PLATFORM_ENV:-test}"
}

ACCEPTANCE_WL_TRACKED=()
acceptance_wl_track() {
  ACCEPTANCE_WL_TRACKED+=("$@")
}

acceptance_wl_cleanup() {
  local root name
  root="$(acceptance_env_dir)"
  for name in "${ACCEPTANCE_WL_TRACKED[@]+"${ACCEPTANCE_WL_TRACKED[@]}"}"; do
    rm -rf "${root:?}/${name}"
  done
}

# Wait until a Platform User systemd unit reports ActiveState=active.
acceptance_wait_user_unit_active() {
  local unit="${1:?unit required}"
  local retries="${2:-60}"
  local state="" _
  for _ in $(seq 1 "${retries}"); do
    state="$(host_ssh bash -s <<REMOTE
set -euo pipefail
UID_NUM=\$(id -u platform)
export XDG_RUNTIME_DIR=/run/user/\${UID_NUM}
runuser -u platform -- env XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR \
  systemctl --user show -p ActiveState --value ${unit} 2>/dev/null || echo ""
REMOTE
)"
    [[ "${state}" == "active" ]] && return 0
    sleep 1
  done
  return 1
}

# Read one process-env key from a running container (podman exec printenv).
# Prints the value; empty stdout and non-zero when missing or unreachable.
acceptance_container_printenv() {
  local cname="${1:?container name required}"
  local key="${2:?env key required}"
  host_ssh env "CNAME=${cname}" "KEY=${key}" bash -s <<'REMOTE'
set -euo pipefail
UID_NUM=$(id -u platform)
HOME_DIR=$(getent passwd platform | cut -d: -f6)
export XDG_RUNTIME_DIR=/run/user/${UID_NUM}
runuser -u platform -- env HOME="${HOME_DIR}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  CNAME="${CNAME}" KEY="${KEY}" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus" \
  bash -c 'cd "$HOME" && podman exec "$CNAME" printenv "$KEY"'
REMOTE
}

# Assert container process environment eventually has KEY=want.
acceptance_assert_container_env() {
  local cname="${1:?container name required}"
  local key="${2:?env key required}"
  local want="${3:?expected value required}"
  local got="" _
  for _ in $(seq 1 30); do
    got="$(acceptance_container_printenv "${cname}" "${key}" 2>/dev/null || true)"
    [[ "${got}" == "${want}" ]] && return 0
    sleep 1
  done
  fail "container ${cname} process env: expected ${key}=${want}, got '${got}'"
}

# Assert KEY is absent from container process environment (after restart/clear).
acceptance_assert_container_env_absent() {
  local cname="${1:?container name required}"
  local key="${2:?env key required}"
  local got="" _
  for _ in $(seq 1 30); do
    got="$(acceptance_container_printenv "${cname}" "${key}" 2>/dev/null || true)"
    [[ -z "${got}" ]] && return 0
    sleep 1
  done
  fail "container ${cname} process env: expected ${key} absent, got '${got}'"
}

# Re-run Component Setup so Edge gathers Route Declarations into interior (ADR-0040).
# Workload Setup / Purge sync SoT only; fulfillment refreshes on Edge Component Setup.
ensure_edge_route_fulfillment() {
  [[ -n "${REPO_ROOT:-}" ]] || fail "ensure_edge_route_fulfillment: REPO_ROOT required"
  "${REPO_ROOT}/internals/ensure-components.sh" --env "${PLATFORM_ENV:-test}"
}
