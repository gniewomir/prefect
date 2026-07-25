#!/usr/bin/env bash
# Host-local Workload Setup. Invoked by prefect/workload-setup.sh (not an operator entrypoint).
# Usage: PREFECT_USER=prefect bash workload-setup-host.sh /path/to/staging-dir
# Staging dir must contain manifest.json and optionally interior.conf.
set -euo pipefail

STAGE="${1:?staging dir required}"
USER_NAME="${PREFECT_USER:-prefect}"
MANIFEST="${STAGE}/manifest.json"
INTERIOR_SRC="${STAGE}/interior.conf"

DATA_ROOT=/var/lib/prefect/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
CLAIMS_DIR="${EDGE_DATA}/claims"
ROUTES_DIR="${EDGE_DATA}/routes"
ACME_DIR="${EDGE_DATA}/acme"
WANT_LIST="${ACME_DIR}/want-list"

# shellcheck source=quadlet-user-session.sh
source /var/lib/prefect/components/lib/quadlet-user-session.sh
# shellcheck source=edge-project-routes-host.sh
source /var/lib/prefect/components/lib/edge-project-routes-host.sh

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
name = m.get("name")
intent = m.get("intent")
upstream = m.get("upstream")
hosts = m.get("public_hostnames") or []
if not name or not isinstance(name, str):
    raise SystemExit("manifest.name must be a non-empty string")
if intent not in ("run", "stop", "trash"):
    raise SystemExit("manifest.intent must be run|stop|trash")
if not upstream or not isinstance(upstream, str):
    raise SystemExit("manifest.upstream must be a non-empty string (host:port)")
if not isinstance(hosts, list) or not hosts or not all(isinstance(h, str) and h for h in hosts):
    raise SystemExit("manifest.public_hostnames must be a non-empty list of strings")
if any(c in name for c in "/ \t\n"):
    raise SystemExit("manifest.name must be a single path segment")
print(f"WL_NAME={shlex.quote(name)}")
print(f"WL_INTENT={shlex.quote(intent)}")
print(f"WL_UPSTREAM={shlex.quote(upstream)}")
print(f"WL_HOSTS={shlex.quote(' '.join(hosts))}")
PY
)"

mkdir -p "${CLAIMS_DIR}" "${ROUTES_DIR}" "${ACME_DIR}" "${WORKLOADS_ROOT}/${WL_NAME}"
[[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"

# Reject interior that tries to own Public Hostnames / listen / TLS.
if [[ -f "${INTERIOR_SRC}" ]]; then
  if grep -Eiq '^\s*(server_name|listen|ssl_certificate|ssl_certificate_key)\b' "${INTERIOR_SRC}"; then
    echo "Workload interior must not declare server_name, listen, or TLS certificate directives" >&2
    exit 1
  fi
fi

# Uniqueness among Intent run/stop claimants (Intent trash releases names).
if [[ "${WL_INTENT}" == "trash" ]]; then
  :
else
  for host in ${WL_HOSTS}; do
    claim_file="${CLAIMS_DIR}/${host}"
    if [[ -f "${claim_file}" ]]; then
      owner="$(cat "${claim_file}")"
      if [[ "${owner}" != "${WL_NAME}" ]]; then
        echo "Public Hostname '${host}' is already claimed by Workload '${owner}' (conflict)" >&2
        exit 1
      fi
    fi
  done
fi

# Drop prior claims owned by this Workload, then re-apply if still claiming.
if [[ -d "${CLAIMS_DIR}" ]]; then
  for claim_file in "${CLAIMS_DIR}"/*; do
    [[ -f "${claim_file}" ]] || continue
    if [[ "$(cat "${claim_file}")" == "${WL_NAME}" ]]; then
      rm -f "${claim_file}"
    fi
  done
fi

if [[ "${WL_INTENT}" != "trash" ]]; then
  for host in ${WL_HOSTS}; do
    printf '%s\n' "${WL_NAME}" >"${CLAIMS_DIR}/${host}"
  done
fi

install -m 0644 "${MANIFEST}" "${WORKLOADS_ROOT}/${WL_NAME}/manifest.json"
if [[ -f "${INTERIOR_SRC}" ]]; then
  install -m 0644 "${INTERIOR_SRC}" "${WORKLOADS_ROOT}/${WL_NAME}/interior.conf"
else
  rm -f "${WORKLOADS_ROOT}/${WL_NAME}/interior.conf"
fi

WL_UPSTREAM_HOST="${WL_UPSTREAM%%:*}"

# Rebuild ACME want-list from Intent run claimants only (ADR-0014 / ADR-0015).
: >"${WANT_LIST}.tmp"
if [[ -d "${WORKLOADS_ROOT}" ]]; then
  for wl_dir in "${WORKLOADS_ROOT}"/*; do
    [[ -d "${wl_dir}" && -f "${wl_dir}/manifest.json" ]] || continue
    python3 - "${wl_dir}/manifest.json" "${WANT_LIST}.tmp" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
if m.get("intent") != "run":
    raise SystemExit(0)
path = sys.argv[2]
with open(path, "a") as f:
    for h in m.get("public_hostnames") or []:
        f.write(f"{h}\n")
PY
  done
fi
sort -u "${WANT_LIST}.tmp" -o "${WANT_LIST}"
rm -f "${WANT_LIST}.tmp"

chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}"

quadlet_user_session_begin

# Project Routes for every stored Manifest (shared with Edge ACME post-issue refresh).
edge_project_routes_from_manifests

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
  # Wait until the Workload answers on the Service Network from the Edge Pod's perspective.
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

# Pick up projected Routes; do not wait for ACME.
edge_reload_front_door_if_routes_changed

# Trigger on-demand ACME immediately when Public Hostnames are claimed/changed (ADR-0015).
# --no-block: Workload Setup must not wait on issuance (ADR-0012).
if quadlet_user systemctl --user --quiet is-enabled edge-acme.timer 2>/dev/null \
  || quadlet_user systemctl --user --quiet is-active edge-acme.timer 2>/dev/null; then
  quadlet_user systemctl --user --no-block start edge-acme.service
fi
