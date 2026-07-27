#!/usr/bin/env bash
# Host-local Workload Setup. Invoked by prefect/workload-setup.sh (not an operator entrypoint).
# Usage: PREFECT_USER=prefect bash workload-setup-host.sh /path/to/staging-dir
# Staging dir must contain manifest.json; optional routes/ tree (operator-authored Route SoT).
# Does not build ACME want-list, claim hostnames, or start ACME (ADR-0023).
set -euo pipefail

STAGE="${1:?staging dir required}"
USER_NAME="${PREFECT_USER:-prefect}"
MANIFEST="${STAGE}/manifest.json"
ROUTES_STAGE="${STAGE}/routes"

DATA_ROOT=/var/lib/prefect/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
ROUTES_DIR="${EDGE_DATA}/routes"

# shellcheck source=quadlet-user-session.sh
source /var/lib/prefect/components/lib/quadlet-user-session.sh
# shellcheck source=edge-routes-host.sh
source /var/lib/prefect/components/lib/edge-routes-host.sh

[[ -f "${MANIFEST}" ]] || {
  echo "manifest.json missing in ${STAGE}" >&2
  exit 1
}

command -v python3 >/dev/null || {
  echo "python3 required on Host for Workload Manifest parsing" >&2
  exit 1
}

eval "$(python3 - "${MANIFEST}" <<'PY'
import json, shlex, sys
m = json.load(open(sys.argv[1]))
if "public_hostnames" in m:
    raise SystemExit(
        "manifest.public_hostnames removed; ACME want-list is Domain assignment (ADR-0023)"
    )
name = m.get("name")
intent = m.get("intent")
upstream = m.get("upstream")
if not name or not isinstance(name, str):
    raise SystemExit("manifest.name must be a non-empty string")
if intent not in ("run", "stop", "trash"):
    raise SystemExit("manifest.intent must be run|stop|trash")
if not upstream or not isinstance(upstream, str):
    raise SystemExit("manifest.upstream must be a non-empty string (host:port)")
if any(c in name for c in "/ \t\n"):
    raise SystemExit("manifest.name must be a single path segment")
print(f"WL_NAME={shlex.quote(name)}")
print(f"WL_INTENT={shlex.quote(intent)}")
print(f"WL_UPSTREAM={shlex.quote(upstream)}")
PY
)"

mkdir -p "${ROUTES_DIR}" "${WORKLOADS_ROOT}/${WL_NAME}"

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

WL_UPSTREAM_HOST="${WL_UPSTREAM%%:*}"

chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}"

quadlet_user_session_begin

# Install operator Routes for Intent run; remove this Workload's installed Routes otherwise.
edge_reconcile_workload_routes "${WL_NAME}" "${WL_INTENT}" "${WORKLOADS_ROOT}/${WL_NAME}/routes"

# Minimal Workload Quadlet on the Service Network (name matches upstream host).
WL_UNIT="${UNIT_DIR}/${WL_UPSTREAM_HOST}.container"
if [[ "${WL_INTENT}" == "run" ]]; then
  cat >"${WL_UNIT}" <<EOF
[Unit]
Description=Prefect Workload ${WL_NAME}

[Container]
Image=docker.io/library/nginx:alpine
ContainerName=${WL_UPSTREAM_HOST}
Network=service-network.network

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  chown "${USER_NAME}:${USER_NAME}" "${WL_UNIT}"
fi
# Intent stop/trash: stop service below; unit file retained until Purge (trash data retained).

quadlet_user_session_reload
quadlet_user systemctl --user reset-failed "${WL_UPSTREAM_HOST}.service" 2>/dev/null || true

if [[ "${WL_INTENT}" == "run" ]]; then
  quadlet_user systemctl --user restart "${WL_UPSTREAM_HOST}.service"
  for _ in $(seq 1 30); do
    if quadlet_user systemctl --user --quiet is-active "${WL_UPSTREAM_HOST}.service"; then
      break
    fi
    sleep 1
  done
  quadlet_user systemctl --user --quiet is-active "${WL_UPSTREAM_HOST}.service"
else
  quadlet_user systemctl --user stop "${WL_UPSTREAM_HOST}.service" 2>/dev/null || true
fi

edge_reload_front_door_if_routes_changed
