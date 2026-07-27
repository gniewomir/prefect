#!/usr/bin/env bash
# Acceptance Test: Intent trash + Purge; Domain-scoped certs survive (#54)
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

plant_fixture_pem() {
  local host="$1"
  ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
CERT_DIR=/var/lib/prefect/components_data/edge/certs/${host}
mkdir -p "\${CERT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "\${CERT_DIR}/privkey.pem" \
  -out "\${CERT_DIR}/fullchain.pem" \
  -days 2 -subj "/CN=${host}" >/dev/null 2>&1
chown -R prefect:prefect /var/lib/prefect/components_data/edge/certs
REMOTE
}

HOST_A="trash-a.example.test"
HOST_B="trash-b.example.test"
HOST_KEEP="keep.example.test"

mkdir -p "${FIX_DIR}/purge-me/routes"
write_manifest "${FIX_DIR}/a-run.json" "trash-a" "run" "${HOST_A}"
write_manifest "${FIX_DIR}/a-trash.json" "trash-a" "trash" "${HOST_A}"
write_manifest "${FIX_DIR}/b-run.json" "reclaim-b" "run" "${HOST_A}"
write_manifest "${FIX_DIR}/b-trash.json" "reclaim-b" "trash" "${HOST_A}"
write_manifest "${FIX_DIR}/keep-stop.json" "keep-me" "stop" "${HOST_KEEP}"
write_manifest "${FIX_DIR}/keep-trash.json" "keep-me" "trash" "${HOST_KEEP}"
write_manifest "${FIX_DIR}/purge-me/manifest.json" "purge-me" "run" "${HOST_B}"
write_manifest "${FIX_DIR}/purge-trash.json" "purge-me" "trash" "${HOST_B}"
cat >"${FIX_DIR}/purge-me/routes/http.conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HOST_B};
    location / { return 200 "purge-probe\n"; add_header Content-Type text/plain; }
}
EOF

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
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/purge-me/manifest.json"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/edge/routes/purge-me--http.conf" \
  || fail "Intent run should install operator Route purge-me--http.conf"
plant_fixture_pem "${HOST_B}"
plant_fixture_pem "${HOST_A}"
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/purge-trash.json"
# Intent trash Setup already uninstalls Routes; plant a leftover so Purge must clear it.
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
printf '%s\n' 'leftover-route' > /var/lib/prefect/components_data/edge/routes/purge-me--http.conf
chown prefect:prefect /var/lib/prefect/components_data/edge/routes/purge-me--http.conf
REMOTE
# Also trash-a is still Intent trash from earlier
"${REPO_ROOT}/prefect/purge-workloads.sh" --env "${PREFECT_ENV:-test}"

ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/purge-me" \
  || fail "Purge should remove Intent trash purge-me data"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test ! -e /var/lib/prefect/components_data/workloads/trash-a" \
  || fail "Purge should remove Intent trash trash-a data"
purge_routes="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "ls /var/lib/prefect/components_data/edge/routes/purge-me.conf /var/lib/prefect/components_data/edge/routes/purge-me--* 2>/dev/null || true")"
[[ -z "${purge_routes}" ]] || fail "Purge should remove installed Routes for trash Workloads (got: ${purge_routes})"
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e /home/prefect/.config/containers/systemd/purge-me.container"; then
  fail "Purge should remove related Quadlet unit for purge-me"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/keep-me/manifest.json" \
  || fail "Purge must not touch Intent stop keep-me"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/reclaim-b/manifest.json" \
  || fail "Purge must not touch Intent run reclaim-b"
if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e /var/lib/prefect/components_data/edge/claims/${HOST_KEEP}"; then
  fail "Intent stop must not hold Public Hostname claim (unique among Intent run only)"
fi
# Domain-scoped certificate material survives Purge (ADR-0022 / #54).
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/edge/certs/${HOST_B}/fullchain.pem \
   && test -f /var/lib/prefect/components_data/edge/certs/${HOST_B}/privkey.pem" \
  || fail "Purge must keep Domain-scoped certificates for ${HOST_B}"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/edge/certs/${HOST_A}/fullchain.pem \
   && test -f /var/lib/prefect/components_data/edge/certs/${HOST_A}/privkey.pem" \
  || fail "Purge must keep Domain-scoped certificates for ${HOST_A} (still used by Intent run)"
want="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat /var/lib/prefect/components_data/edge/acme/want-list")"
echo "${want}" | grep -qx "${HOST_A}" \
  || fail "after Purge, ACME want-list should still include Intent run reclaim-b hostname"
echo "${want}" | grep -qx "${HOST_B}" && fail "after Purge, Intent trash hostname must leave ACME want-list" || true
echo "${want}" | grep -qx "${HOST_KEEP}" && fail "after Purge, Intent stop hostname must not be in ACME want-list" || true
pass "Purge removes trash Workloads/Routes; keeps Domain-scoped certs; want-list is Intent run only"
