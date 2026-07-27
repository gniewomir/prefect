#!/usr/bin/env bash
# Host-local Purge. Invoked by prefect/purge-workloads.sh.
# Removes every Workload whose Intent is trash and Workload-associated data
# (installed Routes, units, Host Volume Workload tree). Does not delete Domains
# or Domain-scoped certificate material (ADR-0022 / #54). Does not rebuild ACME
# want-list (ADR-0023).
set -euo pipefail

USER_NAME="${PREFECT_USER:-prefect}"
DATA_ROOT=/var/lib/prefect/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
ROUTES_DIR="${EDGE_DATA}/routes"

# shellcheck source=quadlet-user-session.sh
source /var/lib/prefect/components/lib/quadlet-user-session.sh
# shellcheck source=edge-routes-host.sh
source /var/lib/prefect/components/lib/edge-routes-host.sh

command -v python3 >/dev/null || {
  echo "python3 required on Host for Purge" >&2
  exit 1
}

quadlet_user_session_begin

if [[ -d "${WORKLOADS_ROOT}" ]]; then
  for wl_dir in "${WORKLOADS_ROOT}"/*; do
    [[ -d "${wl_dir}" && -f "${wl_dir}/manifest.json" ]] || continue
    eval "$(python3 - "${wl_dir}/manifest.json" <<'PY'
import json, shlex, sys
m = json.load(open(sys.argv[1]))
name = m.get("name") or ""
intent = m.get("intent") or ""
upstream = m.get("upstream") or ""
print(f"P_NAME={shlex.quote(name)}")
print(f"P_INTENT={shlex.quote(intent)}")
print(f"P_UPSTREAM={shlex.quote(upstream)}")
PY
)"
    [[ "${P_INTENT}" == "trash" ]] || continue

    upstream_host="${P_UPSTREAM%%:*}"
    if [[ -n "${upstream_host}" ]]; then
      quadlet_user systemctl --user stop "${upstream_host}.service" 2>/dev/null || true
      rm -f "${UNIT_DIR}/${upstream_host}.container"
    fi

    # Installed Routes may already be gone after Intent trash Setup; clear leftovers.
    edge_remove_workload_installed_routes "${P_NAME}"

    rm -rf "${wl_dir}"
  done
fi

chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}" "${HOME_DIR}/.config" 2>/dev/null || true

quadlet_user_session_reload
if quadlet_user systemctl --user --quiet is-active edge-pod.service; then
  quadlet_user systemctl --user restart edge-pod.service
  quadlet_user systemctl --user --quiet is-active edge-pod.service
fi
