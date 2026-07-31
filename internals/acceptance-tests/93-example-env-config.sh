#!/usr/bin/env bash
# Acceptance Test: environments/example env-config teaching Workload (#124 / ADR-0035).
# Materializes the committed example into the active Environment with a local .env,
# Setups it, and asserts EnvironmentFile wiring plus in-container process environment.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_host_session
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

ENV_SLUG="${PLATFORM_ENV:-test}"
WL=env-config
ROLE=app
EXAMPLE_SRC="${REPO_ROOT}/environments/example/${WL}"
EXAMPLE_DOTENV="${REPO_ROOT}/environments/example/.env.example"
FIX_DIR="$(acceptance_env_dir)"
mkdir -p "${FIX_DIR}"
acceptance_wl_track "${WL}"
ENV_FILE="${FIX_DIR}/.env"
GREETING='env-config-greeting-acceptance'
MODE='env-config-mode-acceptance'
trap 'rm -f "${ENV_FILE}"; acceptance_wl_cleanup' EXIT

[[ -d "${EXAMPLE_SRC}" ]] || fail "missing teaching example at environments/example/${WL}"
[[ -f "${EXAMPLE_SRC}/manifest.json" ]] || fail "example missing manifest.json"
[[ -f "${EXAMPLE_SRC}/quadlets/${WL}.pod" ]] || fail "example missing soft-default pod ${WL}.pod"
[[ -f "${EXAMPLE_SRC}/quadlets/${WL}-${ROLE}.container" ]] \
  || fail "example missing member container ${WL}-${ROLE}.container"
[[ -f "${EXAMPLE_DOTENV}" ]] || fail "missing environments/example/.env.example"

python3 - "${EXAMPLE_SRC}/manifest.json" <<'PY' || fail "example Manifest must list EXAMPLE_GREETING and EXAMPLE_MODE"
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
env = m.get("environment")
if not isinstance(env, list):
    raise SystemExit("environment missing or not a list")
need = {"EXAMPLE_GREETING", "EXAMPLE_MODE"}
if set(env) != need:
    raise SystemExit(f"expected environment {sorted(need)}, got {env!r}")
PY
grep -qE '^EXAMPLE_GREETING=' "${EXAMPLE_DOTENV}" \
  || fail ".env.example must document EXAMPLE_GREETING="
grep -qE '^EXAMPLE_MODE=' "${EXAMPLE_DOTENV}" \
  || fail ".env.example must document EXAMPLE_MODE="

grep -qE '^NetworkAlias=env-config$' "${EXAMPLE_SRC}/quadlets/${WL}.pod" \
  || fail "example pod must set NetworkAlias=${WL}"
grep -qE '^Network=service-network\.network$' "${EXAMPLE_SRC}/quadlets/${WL}.pod" \
  || fail "example pod must join Service Network"
grep -qE '^PublishPort=' "${EXAMPLE_SRC}/quadlets/${WL}.pod" \
  && fail "example pod must not PublishPort"
grep -qE '^Volume=.*/workloads/env-config:/var/lib/workload:rw$' \
  "${EXAMPLE_SRC}/quadlets/${WL}-${ROLE}.container" \
  || fail "example container must mount owned tree RW at /var/lib/workload"
grep -qE '^PublishPort=' "${EXAMPLE_SRC}/quadlets/${WL}-${ROLE}.container" \
  && fail "example container must not PublishPort"

rm -rf "${FIX_DIR:?}/${WL:?}"
cp -R "${EXAMPLE_SRC}" "${FIX_DIR}/${WL}"
cat >"${ENV_FILE}" <<EOF
EXAMPLE_GREETING=${GREETING}
EXAMPLE_MODE=${MODE}
EOF
unset EXAMPLE_GREETING EXAMPLE_MODE || true

host_ssh bash -s <<REMOTE
set -euo pipefail
UID_NUM=\$(id -u platform)
export XDG_RUNTIME_DIR=/run/user/\${UID_NUM}
runuser -u platform -- env XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR \
  systemctl --user stop ${WL}-pod.service ${WL}-${ROLE}.service 2>/dev/null || true
rm -rf /var/lib/host-volume/components_data/workloads/${WL} \
  /home/platform/.config/platform/workloads/${WL}
rm -f /home/platform/.config/containers/systemd/${WL}.pod \
  /home/platform/.config/containers/systemd/${WL}-${ROLE}.container
rm -rf /home/platform/.config/containers/systemd/${WL}-${ROLE}.container.d
runuser -u platform -- env XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR systemctl --user daemon-reload
REMOTE

"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"

ENV_PATH="/home/platform/.config/platform/workloads/${WL}/environment"
DROPIN="/home/platform/.config/containers/systemd/${WL}-${ROLE}.container.d/50-platform-environment.conf"

host_ssh "test -f ${ENV_PATH}" || fail "EnvironmentFile missing at ${ENV_PATH}"
env_body="$(host_ssh "cat ${ENV_PATH}")"
echo "${env_body}" | grep -Fq "EXAMPLE_GREETING=${GREETING}" \
  || fail "EnvironmentFile missing EXAMPLE_GREETING"
echo "${env_body}" | grep -Fq "EXAMPLE_MODE=${MODE}" \
  || fail "EnvironmentFile missing EXAMPLE_MODE"
pass "example env-config materializes EnvironmentFile from .env"

host_ssh "test -f ${DROPIN}" || fail "Setup-owned env drop-in missing"
drop_body="$(host_ssh "cat ${DROPIN}")"
echo "${drop_body}" | grep -Fq "EnvironmentFile=${ENV_PATH}" \
  || fail "drop-in must wire EnvironmentFile= path only"
echo "${drop_body}" | grep -Fq "${GREETING}" \
  && fail "bag values must not appear in drop-in text"
pass "example env-config wires Setup-owned EnvironmentFile drop-in"

wait_active() {
  local unit="$1"
  local state=""
  local _
  for _ in $(seq 1 60); do
    state="$(host_ssh bash -s <<REMOTE
set -euo pipefail
UID_NUM=\$(id -u platform)
export XDG_RUNTIME_DIR=/run/user/\${UID_NUM}
runuser -u platform -- env XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR \
  systemctl --user show -p ActiveState --value ${unit} 2>/dev/null || echo ""
REMOTE
)"
    [[ "${state}" == "active" ]] && return 0
    sleep 1
  done
  return 1
}

wait_active "${WL}-pod.service" \
  || fail "Intent run should start Always-on ${WL}-pod.service"
wait_active "${WL}-${ROLE}.service" \
  || fail "Intent run should start Always-on ${WL}-${ROLE}.service"
pass "Always-on pod and member container are active"

probe="$(host_ssh env "GREETING=${GREETING}" "MODE=${MODE}" "WL=${WL}" "ROLE=${ROLE}" bash -s <<'REMOTE'
set -euo pipefail
UID_NUM=$(id -u platform)
HOME_DIR=$(getent passwd platform | cut -d: -f6)
export XDG_RUNTIME_DIR=/run/user/${UID_NUM}
cname="${WL}-${ROLE}"
got_g=""
got_m=""
for _ in $(seq 1 30); do
  got_g=$(runuser -u platform -- env HOME="${HOME_DIR}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus" \
    bash -c 'cd "$HOME" && podman exec '"${cname}"' printenv EXAMPLE_GREETING' 2>/dev/null || true)
  got_m=$(runuser -u platform -- env HOME="${HOME_DIR}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus" \
    bash -c 'cd "$HOME" && podman exec '"${cname}"' printenv EXAMPLE_MODE' 2>/dev/null || true)
  if [[ "${got_g}" == "${GREETING}" && "${got_m}" == "${MODE}" ]]; then
    printf 'ok\n'
    exit 0
  fi
  sleep 1
done
printf 'fail greeting=%s mode=%s\n' "${got_g}" "${got_m}"
exit 1
REMOTE
)" || fail "container process environment missing listed keys (${probe})"
[[ "${probe}" == "ok" ]] || fail "container process environment missing listed keys (${probe})"
pass "container process environment exposes EXAMPLE_GREETING and EXAMPLE_MODE"

sot_grep="$(host_ssh "grep -R -F '${GREETING}' /var/lib/host-volume/components_data/workloads/${WL} 2>/dev/null || true")"
[[ -z "${sot_grep}" ]] || fail "secret must not appear in Host Volume SoT (got: ${sot_grep})"
pass "bag values absent from Host Volume SoT"

cat >"${FIX_DIR}/${WL}/manifest.json" <<'EOF'
{ "intent": "trash" }
EOF
rm -f "${ENV_FILE}"
"${REPO_ROOT}/internals/workload-setup.sh" --env "${ENV_SLUG}" "${WL}"

pass "example env-config Environment Configuration teaching contract"
