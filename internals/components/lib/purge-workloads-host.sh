#!/usr/bin/env bash
# Host-local Purge. Invoked by internals/purge-workloads.sh.
# Removes every Workload whose Intent is trash and Workload-associated data
# (installed Routes, SoT-named Quadlet units, Host Volume Workload tree).
# Does not delete Domains or Domain-scoped certificate material (ADR-0022 / #54).
# Does not rebuild ACME want-list (ADR-0023). Thin Manifest / authored Quadlets: ADR-0024.
set -euo pipefail

USER_NAME="${PLATFORM_USER:-platform}"
DATA_ROOT=/var/lib/host-volume/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
ROUTES_DIR="${EDGE_DATA}/routes"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer sibling shipped with this script (operator tarball); else Host-installed lib.
if [[ -f "${HERE}/workload-quadlets-host.sh" ]]; then
  # shellcheck source=workload-quadlets-host.sh
  source "${HERE}/workload-quadlets-host.sh"
elif [[ -f /var/lib/host-volume/components/lib/workload-quadlets-host.sh ]]; then
  # shellcheck source=workload-quadlets-host.sh
  source /var/lib/host-volume/components/lib/workload-quadlets-host.sh
else
  echo "workload-quadlets-host.sh not found" >&2
  exit 1
fi
# shellcheck source=quadlet-user-session.sh
source /var/lib/host-volume/components/lib/quadlet-user-session.sh
# shellcheck source=edge-routes-host.sh
source /var/lib/host-volume/components/lib/edge-routes-host.sh

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

    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      svc="$(workload_quadlet_service_name "${base}")"
      if [[ -n "${svc}" ]]; then
        quadlet_user systemctl --user stop "${svc}" 2>/dev/null || true
      fi
      rm -f "${UNIT_DIR}/${base}"
    done < <(workload_quadlet_sot_basenames "${wl_dir}/quadlets")

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
