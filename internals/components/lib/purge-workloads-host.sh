#!/usr/bin/env bash
# Host-local Purge. Invoked by internals/purge-workloads.sh.
# Removes every Workload whose Intent is trash and Workload-associated data
# (installed Routes, SoT-named units from both Host unit directories, Host Volume tree,
# Platform User EnvironmentFile tree and Setup-owned Environment Configuration drop-ins).
# Does not delete Domains or Domain-scoped certificate material (ADR-0022 / #54).
# Does not rebuild ACME want-list (ADR-0023). Thin Manifest / authored units: ADR-0024.
# Environment Configuration cleanup: ADR-0035.
set -euo pipefail

USER_NAME="${PLATFORM_USER:-platform}"
DATA_ROOT=/var/lib/host-volume/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
ROUTES_DIR="${EDGE_DATA}/routes"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Staged siblings only (Host delivery packs this payload). No Host Volume dual-read (ADR-0018).
# shellcheck source=workload-quadlets-host.sh
source "${HERE}/workload-quadlets-host.sh"
# shellcheck source=workload-environment-host.sh
source "${HERE}/workload-environment-host.sh"
# shellcheck source=quadlet-user-session.sh
source "${HERE}/quadlet-user-session.sh"
# shellcheck source=edge-routes-host.sh
source "${HERE}/edge-routes-host.sh"

command -v python3 >/dev/null || {
  echo "python3 required on Host for Purge" >&2
  exit 1
}

quadlet_user_session_begin

if [[ -d "${WORKLOADS_ROOT}" ]]; then
  for wl_dir in "${WORKLOADS_ROOT}"/*; do
    [[ -d "${wl_dir}" && -f "${wl_dir}/manifest.json" ]] || continue
    WL_NAME="$(basename "${wl_dir}")"
    eval "$(python3 - "${wl_dir}/manifest.json" <<'PY'
import json, shlex, sys
m = json.load(open(sys.argv[1]))
intent = m.get("intent") or ""
print(f"P_INTENT={shlex.quote(intent)}")
PY
)"
    [[ "${P_INTENT}" == "trash" ]] || continue

    # Remove Environment Configuration before unit/SoT deletion (needs SoT basenames).
    environment_configuration_clear "${WL_NAME}"

    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      workload_unit_stop_basename quadlets "${base}"
      rm -f "${UNIT_DIR}/${base}"
      rm -rf "${UNIT_DIR}/${base}.d"
    done < <(workload_quadlet_sot_basenames "${wl_dir}/quadlets")

    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      workload_unit_stop_basename systemd "${base}"
      rm -f "${SYSTEMD_USER_DIR}/${base}"
      rm -rf "${SYSTEMD_USER_DIR}/${base}.d"
    done < <(workload_quadlet_sot_basenames "${wl_dir}/systemd")

    edge_remove_workload_installed_routes "${WL_NAME}"

    rm -rf "${wl_dir}"
  done
fi

chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}" "${HOME_DIR}/.config" 2>/dev/null || true

quadlet_user_session_reload
if quadlet_user systemctl --user --quiet is-active edge-pod.service; then
  quadlet_user systemctl --user restart edge-pod.service
  quadlet_user systemctl --user --quiet is-active edge-pod.service
fi
