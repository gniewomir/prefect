#!/usr/bin/env bash
# Acceptance Test: Environment Configuration injection via Workload Setup (ADR-0035 / #121)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_host_session
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

ENV_SLUG="${PLATFORM_ENV:-test}"
FIX_DIR="$(acceptance_env_dir)"
mkdir -p "${FIX_DIR}"
WL=envcfg
WL2=envcfg-multi
WL_NC=envcfg-nocontainer
acceptance_wl_track "${WL}" "${WL2}" "${WL_NC}"
ENV_FILE="${FIX_DIR}/.env"
trap 'rm -f "${ENV_FILE}"; acceptance_wl_cleanup' EXIT

SECRET_BASE='envcfg-secret-base-value'
SECRET_OVERRIDE='envcfg-secret-override-value'
SECRET_UNUSED='envcfg-surplus-should-not-appear'

host_cleanup_wl() {
  local name="$1"
  host_ssh \
    "rm -rf /var/lib/host-volume/components_data/workloads/${name} \
            /home/platform/.config/platform/workloads/${name}; \
     rm -f /home/platform/.config/containers/systemd/${name}*.container; \
     rm -rf /home/platform/.config/containers/systemd/${name}*.container.d" \
    || true
}

host_cleanup_wl "${WL}"
host_cleanup_wl "${WL2}"
host_cleanup_wl "${WL_NC}"

write_container() {
  local dir="$1"
  local base="$2"
  local cname="$3"
  mkdir -p "${dir}/quadlets"
  cat >"${dir}/quadlets/${base}.container" <<EOF
[Unit]
Description=Propraetor Environment Configuration probe ${base}

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${cname}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF
}

# --- allowlist: environment accepted; unknown keys still rejected ---
mkdir -p "${FIX_DIR}/${WL}/quadlets"
printf 'ENVCFG_TOKEN=x\nENVCFG_MODE=y\n' >"${ENV_FILE}"
cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVCFG_TOKEN", "ENVCFG_MODE"],
  "public_hostnames": ["nope.example.test"]
}
EOF
write_container "${FIX_DIR}/${WL}" "${WL}" "${WL}"
if "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}" >/dev/null 2>&1; then
  fail "Manifest with unknown keys plus environment must still fail allowlist"
fi
pass "allowlist still rejects unknown keys alongside environment"

cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": "ENVCFG_TOKEN"
}
EOF
if "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}" >/dev/null 2>&1; then
  fail "non-array environment must fail closed"
fi
pass "non-array environment fails closed"

cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVCFG_TOKEN", ""]
}
EOF
if "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}" >/dev/null 2>&1; then
  fail "empty-string environment key must fail closed"
fi
pass "empty-string environment key fails closed"

# --- non-empty environment without .container fails ---
mkdir -p "${FIX_DIR}/${WL_NC}"
cat >"${FIX_DIR}/${WL_NC}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVCFG_TOKEN"]
}
EOF
printf 'ENVCFG_TOKEN=x\n' >"${ENV_FILE}"
if "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL_NC}" >/dev/null 2>&1; then
  fail "non-empty environment without quadlets/*.container must fail closed"
fi
pass "non-empty environment without .container fails closed"

# omit/[] with no containers is fine
cat >"${FIX_DIR}/${WL_NC}/manifest.json" <<'EOF'
{ "intent": "run" }
EOF
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL_NC}"
pass "omit environment with no containers succeeds"

cat >"${FIX_DIR}/${WL_NC}/manifest.json" <<'EOF'
{ "intent": "run", "environment": [] }
EOF
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL_NC}"
pass "[] environment with no containers succeeds"

# --- invalid dotenv fails ---
cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVCFG_TOKEN"]
}
EOF
printf 'export ENVCFG_TOKEN=nope\n' >"${ENV_FILE}"
if "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}" >/dev/null 2>&1; then
  fail "invalid dotenv (export) must fail closed"
fi
pass "invalid dotenv fails closed"

# --- missing listed key fails ---
printf 'ENVCFG_MODE=dev\n' >"${ENV_FILE}"
unset ENVCFG_TOKEN ENVCFG_MODE || true
if ENVCFG_MODE=dev "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}" >/dev/null 2>&1; then
  fail "missing listed key must fail closed"
fi
# restore manifest keys both required
cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVCFG_TOKEN", "ENVCFG_MODE"]
}
EOF
if "${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}" >/dev/null 2>&1; then
  fail "missing ENVCFG_TOKEN must fail closed"
fi
pass "missing listed key fails closed"

# --- happy path: .env baseline + shell override ---
cat >"${ENV_FILE}" <<EOF
ENVCFG_TOKEN=${SECRET_BASE}
ENVCFG_MODE=baseline
ENVCFG_SURPLUS=${SECRET_UNUSED}
EOF
unset ENVCFG_TOKEN ENVCFG_MODE ENVCFG_SURPLUS || true
export ENVCFG_TOKEN="${SECRET_OVERRIDE}"

"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"

ENV_PATH="/home/platform/.config/platform/workloads/${WL}/environment"
DROPIN="/home/platform/.config/containers/systemd/${WL}.container.d/50-platform-environment.conf"
UNIT="/home/platform/.config/containers/systemd/${WL}.container"
SOT="/var/lib/host-volume/components_data/workloads/${WL}"

host_ssh "test -f ${ENV_PATH}" || fail "EnvironmentFile missing at ${ENV_PATH}"
env_body="$(host_ssh "cat ${ENV_PATH}")"
echo "${env_body}" | grep -Fq "ENVCFG_TOKEN=${SECRET_OVERRIDE}" \
  || fail "EnvironmentFile should use shell override for ENVCFG_TOKEN"
echo "${env_body}" | grep -Fq "ENVCFG_MODE=baseline" \
  || fail "EnvironmentFile should keep .env baseline for ENVCFG_MODE"
echo "${env_body}" | grep -Fq "${SECRET_UNUSED}" \
  && fail "surplus bag key must not appear in EnvironmentFile"
echo "${env_body}" | grep -Fq "${SECRET_BASE}" \
  && fail "overridden baseline value must not remain in EnvironmentFile"
pass "EnvironmentFile has listed keys only (.env + shell override)"

host_ssh "test -f ${DROPIN}" || fail "Setup-owned env drop-in missing"
drop_body="$(host_ssh "cat ${DROPIN}")"
echo "${drop_body}" | grep -Fq "EnvironmentFile=${ENV_PATH}" \
  || fail "drop-in must set EnvironmentFile= to Platform User path"
echo "${drop_body}" | grep -Fq "${SECRET_OVERRIDE}" \
  && fail "bag values must not appear in drop-in text"
pass "drop-in wires EnvironmentFile= path only"

sot_grep="$(host_ssh "grep -R -F '${SECRET_OVERRIDE}' ${SOT} 2>/dev/null || true")"
[[ -z "${sot_grep}" ]] || fail "secret must not appear in Host Volume SoT (got: ${sot_grep})"
unit_body="$(host_ssh "cat ${UNIT}")"
echo "${unit_body}" | grep -Fq "${SECRET_OVERRIDE}" \
  && fail "secret must not appear in installed unit body"
pass "bag values absent from Host Volume SoT and unit body"

# --- SoT noop must still refresh Environment Configuration ---
printf 'ENVCFG_TOKEN=%s\nENVCFG_MODE=rotated\n' "${SECRET_OVERRIDE}" >"${ENV_FILE}"
unset ENVCFG_TOKEN || true
export ENVCFG_TOKEN="${SECRET_OVERRIDE}"
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"
env_body2="$(host_ssh "cat ${ENV_PATH}")"
echo "${env_body2}" | grep -Fq "ENVCFG_MODE=rotated" \
  || fail "SoT noop must rewrite EnvironmentFile from current bag"
pass "SoT noop refreshes Environment Configuration"

# --- multiple .container units share one EnvironmentFile path ---
mkdir -p "${FIX_DIR}/${WL2}/quadlets"
cat >"${FIX_DIR}/${WL2}/manifest.json" <<'EOF'
{
  "intent": "run",
  "environment": ["ENVCFG_TOKEN"]
}
EOF
write_container "${FIX_DIR}/${WL2}" "${WL2}-a" "${WL2}-a"
write_container "${FIX_DIR}/${WL2}" "${WL2}-b" "${WL2}-b"
printf 'ENVCFG_TOKEN=%s\n' "${SECRET_OVERRIDE}" >"${ENV_FILE}"
export ENVCFG_TOKEN="${SECRET_OVERRIDE}"
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL2}"

ENV2="/home/platform/.config/platform/workloads/${WL2}/environment"
host_ssh "test -f ${ENV2}" || fail "multi-container Workload missing EnvironmentFile"
for base in "${WL2}-a" "${WL2}-b"; do
  d="/home/platform/.config/containers/systemd/${base}.container.d/50-platform-environment.conf"
  host_ssh "test -f ${d}" || fail "missing drop-in for ${base}"
  body="$(host_ssh "cat ${d}")"
  echo "${body}" | grep -Fq "EnvironmentFile=${ENV2}" \
    || fail "${base} drop-in must point at shared EnvironmentFile"
done
pass "multiple .container units share one EnvironmentFile path"

unset ENVCFG_TOKEN ENVCFG_MODE ENVCFG_SURPLUS || true
pass "Environment Configuration injection contract"
