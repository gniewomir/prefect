#!/usr/bin/env bash
# Acceptance Test: trashed releases names; Purge removes trashed data only
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

write_manifest() {
  local file="$1" name="$2" state="$3" host="$4"
  cat >"${file}" <<EOF
{
  "name": "${name}",
  "state": "${state}",
  "public_hostnames": ["${host}"],
  "upstream": "${name}:80"
}
EOF
}

HOST_A="trash-a.example.test"
HOST_B="trash-b.example.test"
HOST_KEEP="keep.example.test"

write_manifest "${FIX_DIR}/a-running.json" "trash-a" "running" "${HOST_A}"
write_manifest "${FIX_DIR}/a-trashed.json" "trash-a" "trashed" "${HOST_A}"
write_manifest "${FIX_DIR}/b-running.json" "reclaim-b" "running" "${HOST_A}"
write_manifest "${FIX_DIR}/b-trashed.json" "reclaim-b" "trashed" "${HOST_A}"
write_manifest "${FIX_DIR}/keep-stopped.json" "keep-me" "stopped" "${HOST_KEEP}"
write_manifest "${FIX_DIR}/keep-trashed.json" "keep-me" "trashed" "${HOST_KEEP}"
write_manifest "${FIX_DIR}/purge-target.json" "purge-me" "running" "${HOST_B}"
write_manifest "${FIX_DIR}/purge-trashed.json" "purge-me" "trashed" "${HOST_B}"

# Prior runs leave durable Host Volume state — reset these fixtures first.
for m in a-trashed b-trashed keep-trashed purge-trashed; do
  "${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/${m}.json" 2>/dev/null || true
done
"${REPO_ROOT}/prefect/purge-workloads.sh"

"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/a-running.json"
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/a-trashed.json"

# Claims released; data retained; want-list without HOST_A
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e /var/lib/prefect/components_data/edge/claims/${HOST_A}"; then
  fail "trashed should release Public Hostname claim for ${HOST_A}"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/trash-a/manifest.json" \
  || fail "trashed Workload data should remain until Purge"
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx "${HOST_A}" && fail "trashed name must not stay in ACME want-list" || true
pass "trashed releases claims and ACME wants; data retained"

# Reclaim by another Workload
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/b-running.json"
claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/${HOST_A}")"
[[ "${claim}" == "reclaim-b" ]] || fail "reclaim expected reclaim-b, got '${claim}'"
pass "released Public Hostname can be claimed by another Workload Setup"

# Keep a stopped Workload; trash another; Purge should only remove trashed
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/keep-stopped.json"
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/purge-target.json"
"${REPO_ROOT}/prefect/workload-setup.sh" "${FIX_DIR}/purge-trashed.json"
# Also trash-a is still trashed from earlier
"${REPO_ROOT}/prefect/purge-workloads.sh"

ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/purge-me" \
  || fail "Purge should remove trashed purge-me data"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/trash-a" \
  || fail "Purge should remove trashed trash-a data"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/keep-me/manifest.json" \
  || fail "Purge must not touch stopped keep-me"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/reclaim-b/manifest.json" \
  || fail "Purge must not touch running reclaim-b"
keep_claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/${HOST_KEEP}")"
[[ "${keep_claim}" == "keep-me" ]] || fail "stopped claim should survive Purge"
pass "Purge removes trashed Workloads only; running/stopped untouched"
