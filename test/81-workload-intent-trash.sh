#!/usr/bin/env bash
# Acceptance Test: Intent trash releases Public Hostnames; data retained until Purge
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="intent-trash.example.test"
WL=intent-trash
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

# Drop durable leftovers from prior Acceptance Runs for these names.
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
rm -rf /var/lib/prefect/components_data/workloads/${WL} \
  /var/lib/prefect/components_data/workloads/reclaim-intent
rm -f /var/lib/prefect/components_data/edge/claims/${HOST} \
  /var/lib/prefect/components_data/edge/routes/${WL}.conf \
  /var/lib/prefect/components_data/edge/routes/reclaim-intent.conf
REMOTE

write_manifest run
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/${HOST}")"
[[ "${claim}" == "${WL}" ]] || fail "Intent run should claim ${HOST} (got '${claim}')"

write_manifest trash
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/manifest.json"

if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/edge/claims/${HOST}"; then
  fail "Intent trash should release Public Hostname claim for ${HOST}"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/${WL}/manifest.json" \
  || fail "Intent trash Workload data should remain until Purge"
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/edge/routes/${WL}.conf"; then
  fail "Intent trash should remove Workload Route"
fi
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx "${HOST}" && fail "Intent trash name must not stay in ACME want-list" || true
pass "Intent trash releases claims and ACME wants; data retained until Purge"

# Released name can be claimed by another Workload Setup with Intent run
cat >"${FIX_DIR}/reclaim.json" <<EOF
{
  "name": "reclaim-intent",
  "intent": "run",
  "public_hostnames": ["${HOST}"],
  "upstream": "reclaim-intent:80"
}
EOF
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/reclaim.json"
claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/${HOST}")"
[[ "${claim}" == "reclaim-intent" ]] || fail "released name should be claimable (got '${claim}')"
pass "released Public Hostname can be claimed by another Workload Setup"
