#!/usr/bin/env bash
# Workload Quadlet SoT helpers (sourced by Workload Setup).
# Expects: UNIT_DIR (after quadlet_user_session_begin), WORKLOADS_ROOT, USER_NAME.
# Optional: quadlet_user for start/stop after session reload.

# Map a Quadlet unit filename to its user systemd unit (empty if not start/stop managed).
workload_quadlet_service_name() {
  local base="$1"
  local stem="${base%.*}"
  local ext="${base##*.}"
  case "${ext}" in
  container) printf '%s\n' "${stem}.service" ;;
  pod) printf '%s\n' "${stem}-pod.service" ;;
  *) printf '\n' ;;
  esac
}

# List regular non-hidden basenames in a SoT directory (may be missing).
workload_quadlet_sot_basenames() {
  local sot_dir="${1:-}"
  local f base
  [[ -n "${sot_dir}" && -d "${sot_dir}" ]] || return 0
  for f in "${sot_dir}"/*; do
    [[ -f "${f}" ]] || continue
    base="$(basename "${f}")"
    [[ "${base}" == .* ]] && continue
    printf '%s\n' "${base}"
  done
}

# Sync staged quadlets/ into Host Volume SoT for one Workload (replace tree).
workload_quadlet_sync_sot() {
  local wl_name="$1"
  local stage_dir="${2:-}"
  local dest="${WORKLOADS_ROOT}/${wl_name}/quadlets"
  local src

  rm -rf "${dest}"
  if [[ -n "${stage_dir}" && -d "${stage_dir}" ]]; then
    mkdir -p "${dest}"
    for src in "${stage_dir}"/*; do
      [[ -f "${src}" ]] || continue
      [[ "$(basename "${src}")" == .* ]] && continue
      install -m 0644 "${src}" "${dest}/$(basename "${src}")"
    done
  fi
  if [[ -n "${USER_NAME:-}" ]]; then
    chown -R "${USER_NAME}:${USER_NAME}" "${WORKLOADS_ROOT}/${wl_name}" 2>/dev/null || true
  fi
}

# Reconcile UNIT_DIR files to match stored SoT.
# Args: wl_name
# Uses SoT already on Host Volume. prev_bases newline list via stdin or empty.
# Refuse any UNIT_DIR basename that exists and was not in previous SoT for this Workload.
workload_quadlet_reconcile_unit_files() {
  local wl_name="$1"
  local sot_dir="${WORKLOADS_ROOT}/${wl_name}/quadlets"
  local base dest svc
  local -a prev_bases=()
  local -a new_bases=()
  local p n still owned_before

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    prev_bases+=("${base}")
  done

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    new_bases+=("${base}")
  done < <(workload_quadlet_sot_basenames "${sot_dir}")

  for base in "${new_bases[@]+"${new_bases[@]}"}"; do
    dest="${UNIT_DIR}/${base}"
    owned_before=0
    for p in "${prev_bases[@]+"${prev_bases[@]}"}"; do
      if [[ "${p}" == "${base}" ]]; then
        owned_before=1
        break
      fi
    done
    if [[ -e "${dest}" && "${owned_before}" -eq 0 ]]; then
      echo "workload quadlet basename '${base}' already exists in unit directory (not owned by Workload '${wl_name}')" >&2
      return 1
    fi
  done

  for base in "${prev_bases[@]+"${prev_bases[@]}"}"; do
    still=0
    for n in "${new_bases[@]+"${new_bases[@]}"}"; do
      if [[ "${n}" == "${base}" ]]; then
        still=1
        break
      fi
    done
    if [[ "${still}" -eq 0 ]]; then
      svc="$(workload_quadlet_service_name "${base}")"
      if [[ -n "${svc}" ]] && declare -F quadlet_user >/dev/null 2>&1; then
        quadlet_user systemctl --user stop "${svc}" 2>/dev/null || true
      fi
      rm -f "${UNIT_DIR}/${base}"
    fi
  done

  for base in "${new_bases[@]+"${new_bases[@]}"}"; do
    install -m 0644 "${sot_dir}/${base}" "${UNIT_DIR}/${base}"
    if [[ -n "${USER_NAME:-}" ]]; then
      chown "${USER_NAME}:${USER_NAME}" "${UNIT_DIR}/${base}"
    fi
  done
}

# Apply Intent to Quadlet services named by current SoT (after reconcile + reload).
workload_quadlet_apply_intent() {
  local wl_name="$1"
  local intent="$2"
  local sot_dir="${WORKLOADS_ROOT}/${wl_name}/quadlets"
  local base svc _

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    svc="$(workload_quadlet_service_name "${base}")"
    [[ -n "${svc}" ]] || continue
    quadlet_user systemctl --user reset-failed "${svc}" 2>/dev/null || true
    if [[ "${intent}" == "run" ]]; then
      quadlet_user systemctl --user restart "${svc}"
      for _ in $(seq 1 30); do
        if quadlet_user systemctl --user --quiet is-active "${svc}"; then
          break
        fi
        sleep 1
      done
      quadlet_user systemctl --user --quiet is-active "${svc}"
    else
      quadlet_user systemctl --user stop "${svc}" 2>/dev/null || true
    fi
  done < <(workload_quadlet_sot_basenames "${sot_dir}")
}
