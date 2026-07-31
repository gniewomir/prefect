#!/usr/bin/env bash
# Acceptance Test: Environment Configuration rotate / shell-only / omit clear (ADR-0035 / #122)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_host_session
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

ENV_SLUG="${PLATFORM_ENV:-test}"
FIX_DIR="$(acceptance_env_dir)"
mkdir -p "${FIX_DIR}"
WL=envrot
acceptance_wl_track "${WL}"
ENV_FILE="${FIX_DIR}/.env"
trap 'rm -f "${ENV_FILE}"; unset ENVROT_TOKEN ENVROT_MODE ENVROT_SURPLUS || true; acceptance_wl_cleanup' EXIT

SECRET1='envrot-secret-one'
SECRET2='envrot-secret-two'
SURPLUS='envrot-surplus-value'

host_ssh \
  "rm -rf /var/lib/host-volume/components_data/workloads/${WL} \
          /home/platform/.config/platform/workloads/${WL}; \
   rm -f /home/platform/.config/containers/systemd/${WL}.container; \
   rm -rf /home/platform/.config/containers/systemd/${WL}.container.d" \
  || true

mkdir -p "${FIX_DIR}/${WL}/quadlets"
cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVROT_TOKEN", "ENVROT_MODE"]
}
EOF
cat >"${FIX_DIR}/${WL}/quadlets/${WL}.container" <<EOF
[Unit]
Description=Prefect Environment Configuration rotate probe

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${WL}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF

ENV_PATH="/home/platform/.config/platform/workloads/${WL}/environment"
DROPIN="/home/platform/.config/containers/systemd/${WL}.container.d/50-platform-environment.conf"

# --- shell-only (no .env file) ---
rm -f "${ENV_FILE}"
unset ENVROT_TOKEN ENVROT_MODE ENVROT_SURPLUS || true
export ENVROT_TOKEN="${SECRET1}"
export ENVROT_MODE=shell-only
export ENVROT_SURPLUS="${SURPLUS}"

"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"

host_ssh "test -f ${ENV_PATH}" || fail "shell-only Setup should write EnvironmentFile"
body="$(host_ssh "cat ${ENV_PATH}")"
echo "${body}" | grep -Fq "ENVROT_TOKEN=${SECRET1}" || fail "shell-only missing ENVROT_TOKEN"
echo "${body}" | grep -Fq "ENVROT_MODE=shell-only" || fail "shell-only missing ENVROT_MODE"
echo "${body}" | grep -Fq "${SURPLUS}" && fail "surplus shell key must not appear"
pass "shell-only bag resolves without .env; surplus ignored"

# --- rotation with unchanged SoT ---
export ENVROT_TOKEN="${SECRET2}"
export ENVROT_MODE=rotated
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"
body2="$(host_ssh "cat ${ENV_PATH}")"
echo "${body2}" | grep -Fq "ENVROT_TOKEN=${SECRET2}" || fail "rotation should rewrite token"
echo "${body2}" | grep -Fq "ENVROT_MODE=rotated" || fail "rotation should rewrite mode"
echo "${body2}" | grep -Fq "${SECRET1}" && fail "old secret must not remain after rotation"
pass "re-Setup rotates EnvironmentFile with unchanged SoT"

# --- omit removes artifacts ---
cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{ "intent": "run" }
EOF
unset ENVROT_TOKEN ENVROT_MODE ENVROT_SURPLUS || true
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"

host_ssh "test ! -e ${ENV_PATH}" || fail "omit must remove EnvironmentFile"
host_ssh "test ! -d /home/platform/.config/platform/workloads/${WL}" \
  || fail "omit must remove Workload EnvironmentFile tree"
host_ssh "test ! -e ${DROPIN}" || fail "omit must remove Setup-owned env drop-in"
pass "omit removes EnvironmentFile and Setup env drop-ins"

# --- [] removes after re-inject ---
cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVROT_TOKEN"]
}
EOF
export ENVROT_TOKEN="${SECRET1}"
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"
host_ssh "test -f ${ENV_PATH}" || fail "re-inject before [] should write EnvironmentFile"

cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{ "intent": "run", "environment": [] }
EOF
unset ENVROT_TOKEN || true
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"
host_ssh "test ! -e ${ENV_PATH}" || fail "[] must remove EnvironmentFile"
host_ssh "test ! -e ${DROPIN}" || fail "[] must remove Setup-owned env drop-in"
pass "[] removes EnvironmentFile and Setup env drop-ins"

pass "Environment Configuration rotate / shell-only / omit contract"
