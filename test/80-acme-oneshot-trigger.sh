#!/usr/bin/env bash
# Acceptance Test: Workload Setup triggers Edge ACME oneshot when Public Hostnames change
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="acme-trigger.example.test"
FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

cat >"${FIX_DIR}/manifest.json" <<EOF
{
  "name": "acme-trigger",
  "intent": "run",
  "public_hostnames": ["${HOST}"],
  "upstream": "acme-trigger:80"
}
EOF

before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/last-run 2>/dev/null || echo none")"
# Ensure a detectable gap if a prior run left the same second.
sleep 2

"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/last-run 2>/dev/null || echo missing")"
[[ "${after}" != "missing" ]] || fail "ACME oneshot did not write last-run stamp"
[[ "${after}" != "${before}" ]] || fail "ACME oneshot was not triggered (last-run unchanged: ${after})"
pass "Workload Setup starts Edge ACME oneshot when Public Hostnames are claimed"

want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx "${HOST}" || fail "want-list missing ${HOST} after trigger (got: ${want})"
pass "ACME want-list updated for claimed Public Hostname"

timer="$(ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<'REMOTE'
UID_NUM=$(id -u prefect)
export XDG_RUNTIME_DIR=/run/user/${UID_NUM}
if runuser -u prefect -- env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  systemctl --user --quiet is-active edge-acme.timer; then
  echo active
else
  echo inactive
fi
REMOTE
)"
[[ "${timer}" == "active" ]] || fail "periodic edge-acme.timer should remain active"
pass "Periodic systemd user timer remains in place for renewals"

# ACME still does not bind :80/:443 — Edge remains sole publisher (listener owned by edge pod).
publishers="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "ss -ltnp | grep -E ':80|:443' || true")"
echo "${publishers}" | grep -qi 'acme\|lego\|certbot' \
  && fail "ACME client appears to be listening on :80/:443" || true
pass "ACME does not bind :80/:443 (Edge publishes those ports)"
