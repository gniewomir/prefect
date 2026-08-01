#!/usr/bin/env bash
# Host-local Workload Setup. Invoked by internals/workload-setup.sh (not an operator entrypoint).
# Usage: PLATFORM_USER=platform bash workload-setup-host.sh /path/to/workload-tree
# Workload tree must contain manifest.json; optional routes/, quadlets/, systemd/ (ADR-0024).
# Identity is the basename of the Workload tree directory.
# Does not build ACME want-list, claim hostnames, or start ACME (ADR-0023).
set -euo pipefail

TREE="${1:?workload tree required}"
USER_NAME="${PLATFORM_USER:-platform}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${TREE}/manifest.json"
ROUTES_STAGE="${TREE}/routes"
QUADLETS_STAGE="${TREE}/quadlets"
SYSTEMD_STAGE="${TREE}/systemd"

DATA_ROOT=/var/lib/host-volume/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
ROUTES_DIR="${EDGE_DATA}/routes"
WANT_LIST="${EDGE_DATA}/acme/want-list"

# Staged siblings only (Host delivery packs this payload). No Host Volume dual-read (ADR-0018).
# shellcheck source=quadlet-user-session.sh
source "${HERE}/quadlet-user-session.sh"
# shellcheck source=edge-routes-host.sh
source "${HERE}/edge-routes-host.sh"
# shellcheck source=workload-units-host.sh
source "${HERE}/workload-units-host.sh"
# shellcheck source=workload-environment-host.sh
source "${HERE}/workload-environment-host.sh"

[[ -d "${TREE}" ]] || {
  echo "workload tree missing: ${TREE}" >&2
  exit 1
}
[[ -f "${MANIFEST}" ]] || {
  echo "manifest.json missing in ${TREE}" >&2
  exit 1
}

WL_NAME="$(basename "${TREE}")"
if [[ -z "${WL_NAME}" || "${WL_NAME}" == "." || "${WL_NAME}" == ".." ]] ||
  [[ "${WL_NAME}" == */* ]] || [[ "${WL_NAME}" =~ [[:space:]] ]]; then
  echo "workload identity (directory basename) must be a single path segment: '${WL_NAME}'" >&2
  exit 1
fi

command -v python3 >/dev/null || {
  echo "python3 required on Host for Workload Manifest parsing" >&2
  exit 1
}

eval "$(python3 - "${MANIFEST}" <<'PY'
import json, shlex, sys
m = json.load(open(sys.argv[1]))
if not isinstance(m, dict):
    raise SystemExit("manifest must be a JSON object")
allowed = {"intent", "description", "environment"}
extra = sorted(set(m) - allowed)
if extra:
    raise SystemExit("manifest unknown keys (ADR-0024 allowlist): " + ", ".join(extra))
intent = m.get("intent")
if intent not in ("run", "stop", "trash"):
    raise SystemExit("manifest.intent must be run|stop|trash")
if "description" in m and not isinstance(m["description"], str):
    raise SystemExit("manifest.description must be a string when present")
print(f"WL_INTENT={shlex.quote(intent)}")
PY
)"

# Environment Configuration: operator stage_for_setup is the single authority.
# Active iff a resolved file was staged (SSH adapter); Host does not re-parse
# Manifest environment or re-run the containers gate.
WL_ENV_RESOLVED="${WL_ENV_RESOLVED:-}"
if [[ -n "${WL_ENV_RESOLVED}" ]]; then
  [[ -f "${WL_ENV_RESOLVED}" ]] || {
    echo "Environment Configuration resolved file missing: ${WL_ENV_RESOLVED}" >&2
    exit 1
  }
fi

mkdir -p "${ROUTES_DIR}" "${WORKLOADS_ROOT}/${WL_NAME}"

STAGE_UNITS="$(mktemp "${TMPDIR:-/tmp}/platform-stage-units.XXXXXX")"
trap 'rm -f "${STAGE_UNITS}"' EXIT

{
  workload_quadlet_sot_basenames "${QUADLETS_STAGE}"
  workload_quadlet_sot_basenames "${SYSTEMD_STAGE}"
} | LC_ALL=C sort -u >"${STAGE_UNITS}"

quadlet_user_session_begin

# Environment Configuration must run after unit reconcile (drop-ins beside Host
# units) and before daemon-reload / Intent. Registered as the units-module hook.
workload_units_before_reload() {
  environment_configuration_apply_resolved "${WL_NAME}" "${WL_ENV_RESOLVED}"
}

# Noop when definition tree equals Host Volume SoT (ADR-0033). Intent run still
# converges if required unit files are missing (e.g. Host recreated).
SOT_TREE="${WORKLOADS_ROOT}/${WL_NAME}"
if [[ -f "${SOT_TREE}/manifest.json" ]] && diff -rq "${TREE}" "${SOT_TREE}" >/dev/null 2>&1; then
  units_ok=1
  if [[ "${WL_INTENT}" == "run" ]]; then
    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      if ! workload_unit_basename_exists_on_host "${base}"; then
        units_ok=0
        break
      fi
    done <"${STAGE_UNITS}"
  fi
  if [[ "${units_ok}" -eq 1 ]]; then
    # Env refresh/removal must not be skipped by SoT noop (ADR-0035); Intent still applied.
    workload_units_apply "${WL_NAME}" "${WL_INTENT}" "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" || exit 1
    unset -f workload_units_before_reload
    echo "Workload Setup noop: '${WL_NAME}' already matches Host Volume SoT"
    exit 0
  fi
fi

# Refuse foreign / wrong-folder units before mutating Host Volume SoT or Edge.
workload_units_preflight "${WL_NAME}" "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" || exit 1

install -m 0644 "${MANIFEST}" "${WORKLOADS_ROOT}/${WL_NAME}/manifest.json"
rm -f "${WORKLOADS_ROOT}/${WL_NAME}/interior.conf"
rm -rf "${WORKLOADS_ROOT}/${WL_NAME}/routes"
if [[ -d "${ROUTES_STAGE}" ]]; then
  mkdir -p "${WORKLOADS_ROOT}/${WL_NAME}/routes"
  for src in "${ROUTES_STAGE}"/*; do
    [[ -f "${src}" ]] || continue
    install -m 0644 "${src}" "${WORKLOADS_ROOT}/${WL_NAME}/routes/$(basename "${src}")"
  done
fi

edge_reconcile_workload_routes "${WL_NAME}" "${WL_INTENT}" "${WORKLOADS_ROOT}/${WL_NAME}/routes"

workload_units_apply "${WL_NAME}" "${WL_INTENT}" "${QUADLETS_STAGE}" "${SYSTEMD_STAGE}" || exit 1
unset -f workload_units_before_reload

# Cover Host Volume SoT (incl. units synced by apply) and Edge data.
chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}"

edge_reload_front_door_if_routes_changed
