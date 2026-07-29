#!/usr/bin/env bash
# Acceptance Test: Intent trash uninstalls Routes; data retained until Purge (ADR-0024 / ADR-0028)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="$(acceptance_route_fqdn)"
WL="intent-trash"
FIX_DIR="$(mktemp -d)"
trap 'rm -rf "${FIX_DIR}"' EXIT

mkdir -p "${FIX_DIR}/${WL}/quadlets"
if [[ -n "${HOST}" ]]; then
  mkdir -p "${FIX_DIR}/${WL}/routes"
fi
write_manifest() {
  local intent="$1"
  cat >"${FIX_DIR}/${WL}/manifest.json" <<EOF
{
  "intent": "${intent}"
}
EOF
}
if [[ -n "${HOST}" ]]; then
  cat >"${FIX_DIR}/${WL}/routes/${HOST}.conf" <<EOF
location = /trash-probe {
    default_type text/plain;
    return 200 'trash-probe';
}
EOF
fi
cat >"${FIX_DIR}/${WL}/quadlets/${WL}.container" <<EOF
[Unit]
Description=Prefect Workload ${WL}

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${WL}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF

want_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"

ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
rm -rf /var/lib/prefect/components_data/workloads/${WL} \
  /var/lib/prefect/components_data/workloads/reclaim-intent
rm -f /var/lib/prefect/components_data/edge/routes/${WL}.conf \
  /var/lib/prefect/components_data/edge/routes/${WL}--* \
  /var/lib/prefect/components_data/edge/routes/reclaim-intent.conf \
  /var/lib/prefect/components_data/edge/routes/reclaim-intent--*
rm -f /home/prefect/.config/containers/systemd/${WL}.container \
  /home/prefect/.config/containers/systemd/reclaim-intent.container
REMOTE

write_manifest run
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${WL}/manifest.json"

if [[ -n "${HOST}" ]]; then
  ssh "${SSH_OPTS[@]}" "root@${IP}" \
    "test -f /var/lib/prefect/components_data/edge/routes/${WL}--${HOST}.conf" \
    || fail "Intent run should install operator Route ${WL}--${HOST}.conf"
else
  echo "SOFT-SKIP: empty Domain want-list — Route install assertions"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /home/prefect/.config/containers/systemd/${WL}.container" \
  || fail "Intent run should install authored Quadlet"

write_manifest trash
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${WL}/manifest.json"

ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/${WL}/manifest.json" \
  || fail "Intent trash Workload data should remain until Purge"
if [[ -n "${HOST}" ]]; then
  ssh "${SSH_OPTS[@]}" "root@${IP}" \
    "test -f /var/lib/prefect/components_data/workloads/${WL}/routes/${HOST}.conf" \
    || fail "Intent trash should retain Route SoT under Workload tree until Purge"
fi
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /var/lib/prefect/components_data/workloads/${WL}/quadlets/${WL}.container" \
  || fail "Intent trash should retain Quadlet SoT until Purge"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f /home/prefect/.config/containers/systemd/${WL}.container" \
  || fail "Intent trash should retain unit file until Purge"
trash_routes="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "ls /var/lib/prefect/components_data/edge/routes/${WL}.conf /var/lib/prefect/components_data/edge/routes/${WL}--* 2>/dev/null || true")"
[[ -z "${trash_routes}" ]] || fail "Intent trash should remove Workload installed Routes (got: ${trash_routes})"
active="$(ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
UID_NUM=\$(id -u prefect)
export XDG_RUNTIME_DIR=/run/user/\${UID_NUM}
if runuser -u prefect -- env XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR \
  systemctl --user --quiet is-active ${WL}.service 2>/dev/null; then
  echo active
else
  echo inactive
fi
REMOTE
)"
[[ "${active}" == "inactive" ]] || fail "Intent trash: Workload Quadlet should not be active"
want_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"
[[ "${want_after}" == "${want_before}" ]] \
  || fail "Intent trash must not rewrite ACME want-list"
pass "Intent trash uninstalls Routes; stops Quadlets; data retained until Purge; want-list unchanged"

mkdir -p "${FIX_DIR}/reclaim-intent"
cat >"${FIX_DIR}/reclaim-intent/manifest.json" <<EOF
{
  "intent": "run"
}
EOF
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/reclaim-intent/manifest.json"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/workloads/reclaim-intent/manifest.json" \
  || fail "second Workload Setup with Intent run should succeed"
pass "another Workload can Setup Intent run without hostname claims"
