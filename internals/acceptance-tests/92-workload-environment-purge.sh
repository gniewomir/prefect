#!/usr/bin/env bash
# Acceptance Test: Environment Configuration retained on stop/trash; Purge removes it (ADR-0035 / #123)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_host_session
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

ENV_SLUG="${PLATFORM_ENV:-test}"
FIX_DIR="$(acceptance_env_dir)"
mkdir -p "${FIX_DIR}"
WL_STOP=envstop
WL_TRASH=envtrash
WL_KEEP=envkeep
acceptance_wl_track "${WL_STOP}" "${WL_TRASH}" "${WL_KEEP}"
ENV_FILE="${FIX_DIR}/.env"
trap 'rm -f "${ENV_FILE}"; unset ENVPURGE_TOKEN || true; acceptance_wl_cleanup' EXIT

SECRET='envpurge-secret-value'

host_cleanup() {
  local name="$1"
  host_ssh \
    "rm -rf /var/lib/host-volume/components_data/workloads/${name} \
            /home/platform/.config/platform/workloads/${name}; \
     rm -f /home/platform/.config/containers/systemd/${name}.container; \
     rm -rf /home/platform/.config/containers/systemd/${name}.container.d" \
    || true
}

host_cleanup "${WL_STOP}"
host_cleanup "${WL_TRASH}"
host_cleanup "${WL_KEEP}"

stage_wl() {
  local name="$1" intent="$2"
  mkdir -p "${FIX_DIR}/${name}/quadlets"
  cat >"${FIX_DIR}/${name}/manifest.json" <<EOF
{
  "intent": "${intent}",
  "environment": ["ENVPURGE_TOKEN"]
}
EOF
  cat >"${FIX_DIR}/${name}/quadlets/${name}.container" <<EOF
[Unit]
Description=Propraetor Environment Configuration purge probe ${name}

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${name}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF
}

printf 'ENVPURGE_TOKEN=%s\n' "${SECRET}" >"${ENV_FILE}"
export ENVPURGE_TOKEN="${SECRET}"

stage_wl "${WL_STOP}" run
stage_wl "${WL_TRASH}" run
stage_wl "${WL_KEEP}" run

for name in "${WL_STOP}" "${WL_TRASH}" "${WL_KEEP}"; do
  "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${name}"
  host_ssh "test -f /home/platform/.config/platform/workloads/${name}/environment" \
    || fail "${name} should have EnvironmentFile after run Setup"
  host_ssh "test -f /home/platform/.config/containers/systemd/${name}.container.d/50-platform-environment.conf" \
    || fail "${name} should have env drop-in after run Setup"
done
pass "run Setup materializes Environment Configuration for stop/trash/keep Workloads"

# Intent stop retains env artifacts
cat >"${FIX_DIR}/${WL_STOP}/manifest.json" <<EOF
{
  "intent": "stop",
  "environment": ["ENVPURGE_TOKEN"]
}
EOF
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL_STOP}"
host_ssh "test -f /home/platform/.config/platform/workloads/${WL_STOP}/environment" \
  || fail "Intent stop must retain EnvironmentFile"
host_ssh "test -f /home/platform/.config/containers/systemd/${WL_STOP}.container.d/50-platform-environment.conf" \
  || fail "Intent stop must retain Setup env drop-in"
pass "Intent stop retains Environment Configuration"

# Intent trash retains env artifacts
cat >"${FIX_DIR}/${WL_TRASH}/manifest.json" <<EOF
{
  "intent": "trash",
  "environment": ["ENVPURGE_TOKEN"]
}
EOF
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL_TRASH}"
host_ssh "test -f /home/platform/.config/platform/workloads/${WL_TRASH}/environment" \
  || fail "Intent trash must retain EnvironmentFile until Purge"
host_ssh "test -f /home/platform/.config/containers/systemd/${WL_TRASH}.container.d/50-platform-environment.conf" \
  || fail "Intent trash must retain Setup env drop-in until Purge"
pass "Intent trash retains Environment Configuration"

# keep-me stays run (for Purge leave-alone check)
cat >"${FIX_DIR}/${WL_KEEP}/manifest.json" <<EOF
{
  "intent": "run",
  "environment": ["ENVPURGE_TOKEN"]
}
EOF
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL_KEEP}"

"${REPO_ROOT}/internals/purge-workloads.sh" --env "${ENV_SLUG}"

host_ssh "test ! -e /home/platform/.config/platform/workloads/${WL_TRASH}" \
  || fail "Purge must remove trash Workload EnvironmentFile tree"
host_ssh "test ! -e /home/platform/.config/containers/systemd/${WL_TRASH}.container.d/50-platform-environment.conf" \
  || fail "Purge must remove trash Workload Setup env drop-in"
host_ssh "test ! -e /home/platform/.config/containers/systemd/${WL_TRASH}.container" \
  || fail "Purge must remove trash Workload unit"
pass "Purge removes trash Workload Environment Configuration"

host_ssh "test -f /home/platform/.config/platform/workloads/${WL_STOP}/environment" \
  || fail "Purge must leave stop Workload EnvironmentFile alone"
host_ssh "test -f /home/platform/.config/containers/systemd/${WL_STOP}.container.d/50-platform-environment.conf" \
  || fail "Purge must leave stop Workload env drop-in alone"
host_ssh "test -f /home/platform/.config/platform/workloads/${WL_KEEP}/environment" \
  || fail "Purge must leave run Workload EnvironmentFile alone"
host_ssh "test -f /home/platform/.config/containers/systemd/${WL_KEEP}.container.d/50-platform-environment.conf" \
  || fail "Purge must leave run Workload env drop-in alone"
pass "Purge leaves run/stop Workload Environment Configuration alone"

pass "Environment Configuration stop/trash retain and Purge cleanup contract"
