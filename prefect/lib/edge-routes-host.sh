#!/usr/bin/env bash
# Edge Route install helpers and front-door reload (sourced by Workload Setup and Edge ACME).
# Expects: EDGE_DATA, ROUTES_DIR (and optionally WORKLOADS_ROOT).
# Optional: USER_NAME for ownership; when sourced after quadlet_user_session_begin,
#           edge_reload_front_door restarts edge-pod if active.
#
# Sets EDGE_ROUTES_CHANGED=1 when installed Route file contents for a reconcile changed; else 0.

# Remove legacy projected `<name>.conf` and all `<name>--*` installed Routes for one Workload.
edge_remove_workload_installed_routes() {
  local wl_name="$1"
  local f
  rm -f "${ROUTES_DIR}/${wl_name}.conf"
  if compgen -G "${ROUTES_DIR}/${wl_name}--*" >/dev/null; then
    for f in "${ROUTES_DIR}/${wl_name}"--*; do
      rm -f "${f}"
    done
  fi
}

# Reconcile one Workload's installed Routes from SoT dir (Intent run) or remove them.
# Args: workload_name intent routes_sot_dir
# routes_sot_dir may be missing/empty — zero Routes is valid for Intent run.
edge_reconcile_workload_routes() {
  local wl_name="$1"
  local intent="$2"
  local sot_dir="${3:-}"
  local routes_before routes_after
  local src base dest

  mkdir -p "${ROUTES_DIR}"
  EDGE_ROUTES_CHANGED=0

  if compgen -G "${ROUTES_DIR}/*.conf" >/dev/null || compgen -G "${ROUTES_DIR}/*" >/dev/null; then
    routes_before="$(find "${ROUTES_DIR}" -maxdepth 1 -type f -print0 2>/dev/null | sort -z | xargs -0 cat 2>/dev/null | sha256sum)"
  else
    routes_before="none"
  fi

  edge_remove_workload_installed_routes "${wl_name}"

  if [[ "${intent}" == "run" && -n "${sot_dir}" && -d "${sot_dir}" ]]; then
    for src in "${sot_dir}"/*; do
      [[ -f "${src}" ]] || continue
      base="$(basename "${src}")"
      # Skip hidden / non-regular noise; Edge include is *.conf
      [[ "${base}" == *.conf ]] || continue
      dest="${ROUTES_DIR}/${wl_name}--${base}"
      install -m 0644 "${src}" "${dest}"
    done
  fi

  if [[ -n "${USER_NAME:-}" ]]; then
    chown -R "${USER_NAME}:${USER_NAME}" "${ROUTES_DIR}" 2>/dev/null || true
  fi

  if compgen -G "${ROUTES_DIR}/*" >/dev/null; then
    routes_after="$(find "${ROUTES_DIR}" -maxdepth 1 -type f -print0 2>/dev/null | sort -z | xargs -0 cat 2>/dev/null | sha256sum)"
  else
    routes_after="none"
  fi
  if [[ "${routes_before}" != "${routes_after}" ]]; then
    EDGE_ROUTES_CHANGED=1
  fi
}

edge_reload_front_door() {
  local user="${USER_NAME:-prefect}"
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u "${user}" 2>/dev/null || id -u)}"
  local -a cmd
  local _ code

  if [[ "$(id -un)" == "${user}" ]]; then
    cmd=(env "XDG_RUNTIME_DIR=${runtime}" systemctl --user)
  elif declare -F quadlet_user >/dev/null 2>&1; then
    cmd=(quadlet_user systemctl --user)
  else
    return 0
  fi

  if "${cmd[@]}" --quiet is-active edge-pod.service; then
    "${cmd[@]}" restart edge-pod.service
    "${cmd[@]}" --quiet is-active edge-pod.service
    for _ in $(seq 1 30); do
      code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
      if [[ "${code}" =~ ^[0-9]{3}$ ]]; then
        return 0
      fi
      sleep 1
    done
    echo "edge_reload_front_door: Edge did not answer on :80 after restart" >&2
    return 1
  fi
}

# Reload Edge only when installed Routes changed (avoids bouncing :80/:443 on no-op Setup).
edge_reload_front_door_if_routes_changed() {
  if [[ "${EDGE_ROUTES_CHANGED:-0}" == "1" ]]; then
    edge_reload_front_door
  fi
}
