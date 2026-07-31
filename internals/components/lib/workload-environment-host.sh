#!/usr/bin/env bash
# Host-local Environment Configuration materialization (ADR-0035).
# Sourced by workload-setup-host.sh — not an operator entrypoint.
# Requires: HOME_DIR, UNIT_DIR, USER_NAME, WORKLOADS_ROOT (after quadlet_user_session_begin).
#
# workload_environment_path WL_NAME → prints EnvironmentFile absolute path
# workload_environment_reconcile WL_NAME RESOLVED_SRC
#   RESOLVED_SRC empty → remove EnvironmentFile tree + Setup-owned env drop-ins
#   RESOLVED_SRC set  → install EnvironmentFile + Setup-owned drop-ins for each
#                       SoT quadlets/*.container (EnvironmentFile= path only)

workload_environment_path() {
  local wl_name="${1:?workload name required}"
  printf '%s/.config/platform/workloads/%s/environment\n' "${HOME_DIR}" "${wl_name}"
}

workload_environment_dropin_path() {
  local container_base="${1:?container basename required}"
  # container_base includes .container suffix, e.g. app.container
  printf '%s/%s.d/50-platform-environment.conf\n' "${UNIT_DIR}" "${container_base}"
}

workload_environment_remove_dropins_for_dir() {
  local quadlets_dir="${1:-}"
  local base dropin_path dropin_dir
  [[ -d "${quadlets_dir}" ]] || return 0
  for base in "${quadlets_dir}"/*.container; do
    [[ -f "${base}" ]] || continue
    base="$(basename "${base}")"
    dropin_path="$(workload_environment_dropin_path "${base}")"
    dropin_dir="$(dirname "${dropin_path}")"
    rm -f "${dropin_path}"
    if [[ -d "${dropin_dir}" ]] && [[ -z "$(ls -A "${dropin_dir}" 2>/dev/null || true)" ]]; then
      rmdir "${dropin_dir}" 2>/dev/null || true
    fi
  done
}

workload_environment_reconcile() {
  local wl_name="${1:?workload name required}"
  local resolved_src="${2:-}"
  local env_path dropin_path base dest_dir sot_quadlets

  env_path="$(workload_environment_path "${wl_name}")"
  dest_dir="$(dirname "${env_path}")"
  sot_quadlets="${WORKLOADS_ROOT}/${wl_name}/quadlets"

  if [[ -z "${resolved_src}" ]]; then
    workload_environment_remove_dropins_for_dir "${sot_quadlets}"
    rm -rf "${dest_dir}"
    return 0
  fi

  [[ -f "${resolved_src}" ]] || {
    echo "Environment Configuration resolved file missing: ${resolved_src}" >&2
    return 1
  }

  mkdir -p "${dest_dir}"
  install -m 0600 "${resolved_src}" "${env_path}"
  chown -R "${USER_NAME}:${USER_NAME}" "${dest_dir}"

  if [[ ! -d "${sot_quadlets}" ]]; then
    echo "Environment Configuration: no SoT quadlets for '${wl_name}'" >&2
    return 1
  fi

  local found=0
  for base in "${sot_quadlets}"/*.container; do
    [[ -f "${base}" ]] || continue
    found=1
    base="$(basename "${base}")"
    dropin_path="$(workload_environment_dropin_path "${base}")"
    mkdir -p "$(dirname "${dropin_path}")"
    cat >"${dropin_path}" <<EOF
[Container]
EnvironmentFile=${env_path}
EOF
    chown -R "${USER_NAME}:${USER_NAME}" "$(dirname "${dropin_path}")"
  done

  if [[ "${found}" -ne 1 ]]; then
    echo "Environment Configuration requires SoT quadlets/*.container" >&2
    return 1
  fi
  return 0
}
