# Shared helpers for Acceptance Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from test.sh: IP, and for State-backed cases STATE_JSON / HOST_JSON.

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

require_ip() {
  [[ -n "${IP:-}" ]] || fail "fixture missing IP (run via ./test.sh)"
}

# Allowed TCP: open or connection-refused both mean Firewall allowed the packet through.
# Timeout/drop means filtered — fail for allow-listed ports.
probe_allowed_tcp() {
  local port="$1"
  local out
  local rc
  require_ip
  set +e
  out="$(nc -z -w 5 -v "${IP}" "${port}" 2>&1)"
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
