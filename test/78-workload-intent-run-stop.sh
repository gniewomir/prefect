#!/usr/bin/env bash
# Acceptance Test: Intent run with authored Quadlet + operator Route fragment; Intent stop
# (ADR-0024 / ADR-0028). Soft-skips Route attach when Domain want-list is empty.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

HOST="$(acceptance_route_fqdn)"
WL=app
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
location = /app-route-probe {
    default_type text/plain;
    return 200 'app-route-ok';
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

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "rm -rf /var/lib/prefect/components_data/edge/routes/${WL}.conf \
          /var/lib/prefect/components_data/edge/routes/${WL}--* \
          /var/lib/prefect/components_data/workloads/${WL}; \
   rm -f /home/prefect/.config/containers/systemd/${WL}.container"

write_manifest run
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${WL}/manifest.json"

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /var/lib/prefect/components_data/workloads/${WL}/quadlets/${WL}.container" \
  || fail "Intent run should store authored Quadlet SoT"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /home/prefect/.config/containers/systemd/${WL}.container" \
  || fail "Intent run should install authored Quadlet unit file"
pass "Intent run installs authored Quadlet"

if [[ -n "${HOST}" ]]; then
  ssh "${SSH_OPTS[@]}" "root@${IP}" \
    "test -f /var/lib/prefect/components_data/edge/routes/${WL}--${HOST}.conf" \
    || fail "Intent run should install Route fragment ${WL}--${HOST}.conf"
  pass "Intent run installs FQDN-keyed Route fragment"
else
  echo "SOFT-SKIP: empty Domain want-list — Route install/stop assertions"
fi

write_manifest stop
"${REPO_ROOT}/prefect/workload-setup.sh" --env "${PREFECT_ENV:-test}" "${FIX_DIR}/${WL}/manifest.json"

if [[ -n "${HOST}" ]]; then
  stop_routes="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
    "ls /var/lib/prefect/components_data/edge/routes/${WL}.conf /var/lib/prefect/components_data/edge/routes/${WL}--* 2>/dev/null || true")"
  [[ -z "${stop_routes}" ]] || fail "Intent stop must remove Workload installed Routes (got: ${stop_routes})"
  pass "Intent stop removes Workload installed Routes from Edge"
fi

ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f /home/prefect/.config/containers/systemd/${WL}.container" \
  || fail "Intent stop should retain unit file until Purge"
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
[[ "${active}" == "inactive" ]] || fail "Intent stop: Workload Quadlet should not be active"
pass "Intent stop: Workload Quadlets are inactive; unit file retained"

want_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "cat /var/lib/prefect/components_data/edge/acme/want-list 2>/dev/null || true")"
[[ "${want_after}" == "${want_before}" ]] \
  || fail "Intent stop must not rewrite ACME want-list"
pass "Intent stop leaves Domain ACME want-list unchanged"

if [[ -n "${HOST}" ]]; then
  # Fragment gone; Domain front /healthcheck remains (83). Probe path should miss.
  ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
UID_NUM="\$(id -u prefect)"
export XDG_RUNTIME_DIR="/run/user/\${UID_NUM}"
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" systemctl --user restart edge-pod.service
REMOTE
  code=""
  for _ in $(seq 1 30); do
    code="$(curl -skS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 \
      --resolve "${HOST}:443:${IP}" "https://${HOST}/app-route-probe" 2>/dev/null || true)"
    [[ "${code}" == "404" ]] && break
    sleep 1
  done
  [[ "${code}" == "404" ]] \
    || fail "Intent stop: Route fragment path should miss (HTTP 404), got '${code}'"
  pass "Intent stop: previously attached Route path misses on Domain front"
fi
