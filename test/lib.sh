# Shared helpers for Acceptance Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from test.sh: IP, and for State-backed cases STATE_JSON / HOST_JSON.

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

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

# Populate SSH_OPTS for pubkey BatchMode sessions. Optional: VERIFY_SSH_IDENTITY.
acceptance_ssh_opts() {
  SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
  if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
    SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
  fi
}

# Run the Host-local carrier-ready gate over SSH (IHP done, floor, Prefect User, mount).
# Requires: IP, SSH_OPTS (acceptance_ssh_opts), REPO_ROOT. Optional: PREFECT_USER.
wait_until_carrier_ready() {
  require_ip
  [[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"
  local script="${REPO_ROOT}/prefect/lib/wait-until-carrier-ready.sh"
  [[ -f "${script}" ]] || fail "missing ${script}"
  local user="${PREFECT_USER:-prefect}"
  if ! ssh "${SSH_OPTS[@]}" "root@${IP}" "PREFECT_USER=${user} bash -s" <"${script}"; then
    fail "Host not ready for Component Setup (see Host output above)"
  fi
}
