#!/usr/bin/env bash
# Host-local Purge. Invoked by prefect/purge-workloads.sh.
# Removes every trashed Workload and associated Routes, certificates, units, and Host Volume data.
set -euo pipefail

USER_NAME="${PREFECT_USER:-prefect}"
DATA_ROOT=/var/lib/prefect/components_data
EDGE_DATA="${DATA_ROOT}/edge"
WORKLOADS_ROOT="${DATA_ROOT}/workloads"
CLAIMS_DIR="${EDGE_DATA}/claims"
ROUTES_DIR="${EDGE_DATA}/routes"
CERTS_DIR="${EDGE_DATA}/certs"
ACME_DIR="${EDGE_DATA}/acme"
WANT_LIST="${ACME_DIR}/want-list"

# shellcheck source=quadlet-user-session.sh
source /var/lib/prefect/components/lib/quadlet-user-session.sh

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
state = m.get("state") or ""
upstream = m.get("upstream") or ""
hosts = m.get("public_hostnames") or []
print(f"P_NAME={shlex.quote(name)}")
print(f"P_STATE={shlex.quote(state)}")
print(f"P_UPSTREAM={shlex.quote(upstream)}")
print(f"P_HOSTS={shlex.quote(' '.join(hosts) if isinstance(hosts, list) else '')}")
PY
)"
    [[ "${P_STATE}" == "trashed" ]] || continue

    upstream_host="${P_UPSTREAM%%:*}"
    if [[ -n "${upstream_host}" ]]; then
      quadlet_user systemctl --user stop "${upstream_host}.service" 2>/dev/null || true
      rm -f "${UNIT_DIR}/${upstream_host}.container"
    fi

    rm -f "${ROUTES_DIR}/${P_NAME}.conf"
    for host in ${P_HOSTS}; do
      rm -rf "${CERTS_DIR}/${host}"
      # Claims should already be released on trash; clear any stale file.
      if [[ -f "${CLAIMS_DIR}/${host}" ]] && [[ "$(cat "${CLAIMS_DIR}/${host}")" == "${P_NAME}" ]]; then
        rm -f "${CLAIMS_DIR}/${host}"
      fi
    done
    rm -rf "${wl_dir}"
  done
fi

# Rebuild want-list from remaining running Workloads.
mkdir -p "${ACME_DIR}"
: >"${WANT_LIST}.tmp"
if [[ -d "${WORKLOADS_ROOT}" ]]; then
  for wl_dir in "${WORKLOADS_ROOT}"/*; do
    [[ -d "${wl_dir}" && -f "${wl_dir}/manifest.json" ]] || continue
    python3 - "${wl_dir}/manifest.json" "${WANT_LIST}.tmp" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
if m.get("state") != "running":
    raise SystemExit(0)
with open(sys.argv[2], "a") as f:
    for h in m.get("public_hostnames") or []:
        f.write(f"{h}\n")
PY
  done
fi
sort -u "${WANT_LIST}.tmp" -o "${WANT_LIST}"
rm -f "${WANT_LIST}.tmp"

chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}" "${HOME_DIR}/.config" 2>/dev/null || true

quadlet_user_session_reload
if quadlet_user systemctl --user --quiet is-active edge-pod.service; then
  quadlet_user systemctl --user restart edge-pod.service
  quadlet_user systemctl --user --quiet is-active edge-pod.service
fi
