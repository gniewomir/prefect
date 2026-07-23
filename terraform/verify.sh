#!/usr/bin/env bash
# Applied Stack observability — operator verification after terraform apply.
# Asserts external behavior only (spec #1). Requires: terraform, jq, nc, ssh, ping; applied State.
# Optional: VERIFY_SSH_IDENTITY=/path/to/private_key (defaults to ssh agent / default identities).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

command -v terraform >/dev/null || fail "terraform not found"
command -v jq >/dev/null || fail "jq not found"
command -v nc >/dev/null || fail "nc not found"
command -v ssh >/dev/null || fail "ssh not found"
command -v ping >/dev/null || fail "ping not found"

IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (apply the Stack first)"

echo "Checking Reserved IP ${IP} ..."

# Host metadata from State (name, region, size, image, tag)
STATE_JSON="$(terraform show -json)"
HOST_JSON="$(echo "${STATE_JSON}" | jq -c '
  .values.root_module.resources[]
  | select(.type == "digitalocean_droplet" and .name == "web")
  | .values
')"
[[ -n "${HOST_JSON}" && "${HOST_JSON}" != "null" ]] || fail "Host digitalocean_droplet.web not in State"

echo "${HOST_JSON}" | jq -e '.name == "prefect-web"' >/dev/null || fail "Host name != prefect-web"
echo "${HOST_JSON}" | jq -e '.region == "fra1"' >/dev/null || fail "Host region != fra1"
echo "${HOST_JSON}" | jq -e '.size == "s-1vcpu-512mb-10gb"' >/dev/null || fail "Host size mismatch"
echo "${HOST_JSON}" | jq -e '.image == "ubuntu-24-04-x64"' >/dev/null || fail "Host image mismatch"
echo "${HOST_JSON}" | jq -e '.tags | index("prefect") != null' >/dev/null || fail "Host missing Office Tag prefect"
echo "${HOST_JSON}" | jq -e '.tags | index("prefect-public-web") != null' >/dev/null || fail "Host missing Role Tag prefect-public-web"
pass "Host metadata (name, region, size, image, Office Tag, Role Tag)"

ASSIGNED="$(echo "${STATE_JSON}" | jq -r '
  .values.root_module.resources[]
  | select(.type == "digitalocean_reserved_ip" and .name == "web")
  | .values.ip_address
')"
[[ "${ASSIGNED}" == "${IP}" ]] || fail "Reserved IP output ${IP} != State ${ASSIGNED}"
pass "Reserved IP assigned and exported"

PROJECT_JSON="$(echo "${STATE_JSON}" | jq -c '
  .values.root_module.resources[]
  | select(.type == "digitalocean_project" and .name == "prefect")
  | .values
')"
[[ -n "${PROJECT_JSON}" && "${PROJECT_JSON}" != "null" ]] || fail "Cloud Project digitalocean_project.prefect not in State"
echo "${PROJECT_JSON}" | jq -e '.name == "Prefect"' >/dev/null || fail "Cloud Project name != Prefect"
echo "${PROJECT_JSON}" | jq -e '.environment == "Production"' >/dev/null || fail "Cloud Project environment != Production"
echo "${PROJECT_JSON}" | jq -e '.is_default == false' >/dev/null || fail "Cloud Project must not be account default"
HOST_URN="$(echo "${HOST_JSON}" | jq -r '.urn')"
echo "${PROJECT_JSON}" | jq -e --arg urn "${HOST_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Host URN not assigned to Cloud Project Prefect"
pass "Cloud Project Prefect owns Host"

# ICMP allowed
if ping -c 2 -W 5 "${IP}" >/dev/null 2>&1; then
  pass "inbound ICMP reaches Host"
else
  fail "inbound ICMP to ${IP} failed"
fi

# Allowed TCP: open or connection-refused both mean Firewall allowed the packet through.
# Timeout/drop means filtered — fail for allow-listed ports.
probe_allowed_tcp() {
  local port="$1"
  local out
  set +e
  out="$(nc -z -w 5 -v "${IP}" "${port}" 2>&1)"
  local rc=$?
  set -e
  if [[ ${rc} -eq 0 ]] || echo "${out}" | grep -qi "refused"; then
    pass "inbound TCP ${port} not filtered"
  else
    fail "inbound TCP ${port} appears filtered/unreachable"
  fi
}

for port in 22 80 443; do
  probe_allowed_tcp "${port}"
done

# Denied TCP: Firewall should DROP (timeout), not allow through to a closed port (refused).
set +e
DENY_OUT="$(nc -z -w 5 -v "${IP}" 25 2>&1)"
DENY_RC=$?
set -e
if [[ ${DENY_RC} -eq 0 ]]; then
  fail "inbound TCP 25 unexpectedly accepted"
elif echo "${DENY_OUT}" | grep -qi "refused"; then
  fail "inbound TCP 25 reached Host (connection refused) — Firewall likely allowing it"
else
  pass "inbound TCP 25 filtered (denied by Firewall)"
fi

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o PreferredAuthentications=publickey)
if [[ -n "${VERIFY_SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${VERIFY_SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

if ssh "${SSH_OPTS[@]}" "root@${IP}" "true" 2>/dev/null; then
  pass "SSH public-key auth to root@${IP}"
else
  fail "SSH public-key auth to root@${IP} failed (set VERIFY_SSH_IDENTITY or load the matching key)"
fi

# Outbound smoke from the Host
if ssh "${SSH_OPTS[@]}" "root@${IP}" "curl -fsS -o /dev/null -w '%{http_code}' --connect-timeout 10 https://example.com" 2>/dev/null | grep -Eq '^[23][0-9][0-9]$'; then
  pass "outbound HTTPS from Host"
else
  fail "outbound HTTPS smoke from Host failed"
fi

# Password auth must not be offered (BatchMode exit alone is a false positive).
set +e
SSH_PW_OUT="$(ssh -v -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=10 -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=0 \
  "root@${IP}" "true" 2>&1)"
SSH_PW_RC=$?
set -e

echo "${SSH_PW_OUT}" | grep -q "Authentications that can continue" \
  || fail "SSH password check did not reach auth negotiation"

if echo "${SSH_PW_OUT}" | grep -E "Authentications that can continue:.*(password|keyboard-interactive)" >/dev/null; then
  fail "SSH password auth unexpectedly offered by server"
fi

[[ ${SSH_PW_RC} -ne 0 ]] || fail "SSH password auth unexpectedly succeeded"
pass "SSH password auth not offered"

echo "All Applied Stack observability checks passed."
