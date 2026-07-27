#!/usr/bin/env bash
# Acceptance Test: Intent trash releases names; Purge removes Intent-trash data only
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

write_manifest() {
  local file="$1" name="$2" intent="$3" host="$4"
  cat >"${file}" <<EOF
{
  "name": "${name}",
  "intent": "${intent}",
  "public_hostnames": ["${host}"],
  "upstream": "${name}:80"
}
EOF
}

HOST_A="trash-a.example.test"
HOST_B="trash-b.example.test"
HOST_KEEP="keep.example.test"

write_manifest "${FIX_DIR}/a-run.json" "trash-a" "run" "${HOST_A}"
write_manifest "${FIX_DIR}/a-trash.json" "trash-a" "trash" "${HOST_A}"
write_manifest "${FIX_DIR}/b-run.json" "reclaim-b" "run" "${HOST_A}"
write_manifest "${FIX_DIR}/b-trash.json" "reclaim-b" "trash" "${HOST_A}"
write_manifest "${FIX_DIR}/keep-stop.json" "keep-me" "stop" "${HOST_KEEP}"
write_manifest "${FIX_DIR}/keep-trash.json" "keep-me" "trash" "${HOST_KEEP}"
write_manifest "${FIX_DIR}/purge-target.json" "purge-me" "run" "${HOST_B}"
write_manifest "${FIX_DIR}/purge-trash.json" "purge-me" "trash" "${HOST_B}"

# Prior runs leave durable Host Volume state — reset these fixtures first.
for m in a-trash b-trash keep-trash purge-trash; do
  "${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${m}.json" 2>/dev/null || true
done
"${REPO_ROOT}/prefect/purge-workloads.sh" --env "${PREFECT_ENV:-test}"

"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/a-run.json"
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/a-trash.json"

# Claims released; data retained; want-list without HOST_A
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e /var/lib/prefect/components_data/edge/claims/${HOST_A}"; then
  fail "Intent trash should release Public Hostname claim for ${HOST_A}"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/trash-a/manifest.json" \
  || fail "Intent trash Workload data should remain until Purge"
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx "${HOST_A}" && fail "Intent trash name must not stay in ACME want-list" || true
pass "Intent trash releases claims and ACME wants; data retained"

# Reclaim by another Workload
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/b-run.json"
claim="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/claims/${HOST_A}")"
[[ "${claim}" == "reclaim-b" ]] || fail "reclaim expected reclaim-b, got '${claim}'"
pass "released Public Hostname can be claimed by another Workload Setup"

# Keep Intent stop; trash another; Purge should only remove Intent trash
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/keep-stop.json"
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/purge-target.json"
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/purge-trash.json"
# Also trash-a is still Intent trash from earlier
"${REPO_ROOT}/prefect/purge-workloads.sh" --env "${PREFECT_ENV:-test}"

ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/purge-me" \
  || fail "Purge should remove Intent trash purge-me data"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/trash-a" \
  || fail "Purge should remove Intent trash trash-a data"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/keep-me/manifest.json" \
  || fail "Purge must not touch Intent stop keep-me"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/reclaim-b/manifest.json" \
  || fail "Purge must not touch Intent run reclaim-b"
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e /var/lib/prefect/components_data/edge/claims/${HOST_KEEP}"; then
  fail "Intent stop must not hold Public Hostname claim (unique among Intent run only)"
fi
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx "${HOST_A}" \
  || fail "after Purge, ACME want-list should still include Intent run reclaim-b hostname"
echo "${want}" | grep -qx "${HOST_B}" && fail "after Purge, Intent trash hostname must leave ACME want-list" || true
echo "${want}" | grep -qx "${HOST_KEEP}" && fail "after Purge, Intent stop hostname must not be in ACME want-list" || true
pass "Purge removes Workloads whose Intent is trash only; run/stop untouched"
