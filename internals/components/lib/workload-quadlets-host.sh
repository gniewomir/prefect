#!/usr/bin/env bash
# Workload unit SoT helpers for dual consumers (sourced by Workload Setup / Purge).
# Expects after quadlet_user_session_begin: UNIT_DIR, SYSTEMD_USER_DIR, WORKLOADS_ROOT, USER_NAME.
# Optional: quadlet_user for start/stop after session reload.
#
# Consumers: quadlets/ → UNIT_DIR; systemd/ → SYSTEMD_USER_DIR (ADR-0024 / ADR-0034).
# Basename ownership spans both Host unit directories. Wrong-folder authoring fails closed.

# True when unit file has Key=value (comments and surrounding whitespace ignored).
workload_unit_file_key_equals() {
  local file="$1"
  local key="$2"
  local want="$3"
  local line k v
  [[ -f "${file}" ]] || return 1
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "${line}" ]] || continue
    [[ "${line}" == *=* ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    k="${k%"${k##*[![:space:]]}"}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [[ "${k}" == "${key}" && "${v}" == "${want}" ]]; then
      return 0
    fi
  done <"${file}"
  return 1
}

# Map a Quadlet unit filename to its generated user systemd unit (empty if none).
workload_quadlet_service_name() {
  local base="$1"
  local stem="${base%.*}"
  local ext="${base##*.}"
  case "${ext}" in
  container | kube) printf '%s\n' "${stem}.service" ;;
  pod) printf '%s\n' "${stem}-pod.service" ;;
  volume) printf '%s\n' "${stem}-volume.service" ;;
  network) printf '%s\n' "${stem}-network.service" ;;
  image) printf '%s\n' "${stem}-image.service" ;;
  build) printf '%s\n' "${stem}-build.service" ;;
  artifact) printf '%s\n' "${stem}-artifact.service" ;;
  *) printf '\n' ;;
  esac
}

# Map a native systemd unit filename to itself when Intent-managed (empty otherwise).
workload_systemd_unit_name() {
  local base="$1"
  local ext="${base##*.}"
  case "${ext}" in
  service | timer) printf '%s\n' "${base}" ;;
  *) printf '\n' ;;
  esac
}

# Classify authored unit by file kind: always-on | on-demand | ensure (empty = install-only).
# Args: consumer (quadlets|systemd) base sot_file
workload_unit_kind() {
  local consumer="$1"
  local base="$2"
  local file="$3"
  local ext="${base##*.}"

  case "${consumer}" in
  quadlets)
    case "${ext}" in
    volume | network | image | build | artifact)
      printf '%s\n' ensure
      ;;
    container)
      if workload_unit_file_key_equals "${file}" StartWithPod false; then
        printf '%s\n' on-demand
      else
        printf '%s\n' always-on
      fi
      ;;
    pod | kube)
      printf '%s\n' always-on
      ;;
    *)
      printf '\n'
      ;;
    esac
    ;;
  systemd)
    case "${ext}" in
    timer)
      printf '%s\n' on-demand
      ;;
    service)
      if workload_unit_file_key_equals "${file}" Type oneshot; then
        printf '%s\n' on-demand
      else
        printf '%s\n' always-on
      fi
      ;;
    *)
      printf '\n'
      ;;
    esac
    ;;
  *)
    printf '\n'
    ;;
  esac
}

# True when extension belongs under authored quadlets/.
workload_unit_ext_is_quadlet() {
  case "$1" in
  container | pod | kube | network | volume | image | build | artifact) return 0 ;;
  *) return 1 ;;
  esac
}

# True when extension belongs under authored systemd/.
workload_unit_ext_is_native() {
  case "$1" in
  service | timer | socket | path | target | slice | mount | automount | swap) return 0 ;;
  *) return 1 ;;
  esac
}

# Fail closed if any regular file in stage_dir has the wrong consumer extension.
# Args: consumer (quadlets|systemd) stage_dir (may be missing/empty — valid)
workload_unit_validate_consumer_dir() {
  local consumer="$1"
  local stage_dir="${2:-}"
  local f base ext
  [[ -n "${stage_dir}" && -d "${stage_dir}" ]] || return 0
  for f in "${stage_dir}"/*; do
    [[ -f "${f}" ]] || continue
    base="$(basename "${f}")"
    [[ "${base}" == .* ]] && continue
    ext="${base##*.}"
    if [[ "${base}" == "${ext}" ]]; then
      echo "workload ${consumer}/ file '${base}' has no extension (wrong-folder / invalid unit)" >&2
      return 1
    fi
    case "${consumer}" in
    quadlets)
      if workload_unit_ext_is_quadlet "${ext}"; then
        continue
      fi
      if workload_unit_ext_is_native "${ext}"; then
        echo "workload unit '${base}' authored under quadlets/ but belongs in systemd/ (wrong-folder)" >&2
        return 1
      fi
      echo "workload quadlets/ file '${base}' has unsupported extension '.${ext}'" >&2
      return 1
      ;;
    systemd)
      if workload_unit_ext_is_native "${ext}"; then
        continue
      fi
      if workload_unit_ext_is_quadlet "${ext}"; then
        echo "workload unit '${base}' authored under systemd/ but belongs in quadlets/ (wrong-folder)" >&2
        return 1
      fi
      echo "workload systemd/ file '${base}' has unsupported extension '.${ext}'" >&2
      return 1
      ;;
    *)
      echo "workload_unit_validate_consumer_dir: unknown consumer '${consumer}'" >&2
      return 1
      ;;
    esac
  done
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

# True when basename exists in either Host unit directory.
workload_unit_basename_exists_on_host() {
  local base="$1"
  [[ -e "${UNIT_DIR}/${base}" || -e "${SYSTEMD_USER_DIR}/${base}" ]]
}

# Refuse basename if present in either Host unit directory and not previously owned.
# Args: wl_name base prev_owned_file (union of previous SoT basenames)
workload_unit_refuse_foreign_basename() {
  local wl_name="$1"
  local base="$2"
  local prev_file="$3"
  local owned_before=0
  local p

  while IFS= read -r p; do
    [[ -n "${p}" ]] || continue
    if [[ "${p}" == "${base}" ]]; then
      owned_before=1
      break
    fi
  done <"${prev_file}"

  if workload_unit_basename_exists_on_host "${base}" && [[ "${owned_before}" -eq 0 ]]; then
    echo "workload unit basename '${base}' already exists in a Host unit directory (not owned by Workload '${wl_name}')" >&2
    return 1
  fi
}

# Sync staged consumer dir into Host Volume SoT for one Workload (replace tree).
# Args: wl_name consumer (quadlets|systemd) stage_dir
workload_unit_sync_sot() {
  local wl_name="$1"
  local consumer="$2"
  local stage_dir="${3:-}"
  local dest="${WORKLOADS_ROOT}/${wl_name}/${consumer}"
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

# Stop a managed unit for one consumer basename (best-effort).
workload_unit_stop_basename() {
  local consumer="$1"
  local base="$2"
  local svc=""
  case "${consumer}" in
  quadlets) svc="$(workload_quadlet_service_name "${base}")" ;;
  systemd) svc="$(workload_systemd_unit_name "${base}")" ;;
  esac
  if [[ -n "${svc}" ]] && declare -F quadlet_user >/dev/null 2>&1; then
    quadlet_user systemctl --user stop "${svc}" 2>/dev/null || true
  fi
}

# Reconcile one consumer: drop removed (prev_drop), install new; refuse foreign via prev_owned.
# Args: wl_name consumer dest_dir prev_drop_file prev_owned_file
workload_unit_reconcile_consumer() {
  local wl_name="$1"
  local consumer="$2"
  local dest_dir="$3"
  local prev_drop="$4"
  local prev_owned="$5"
  local sot_dir="${WORKLOADS_ROOT}/${wl_name}/${consumer}"
  local base
  local -a prev_bases=()
  local -a new_bases=()
  local n still

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    prev_bases+=("${base}")
  done <"${prev_drop}"

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    new_bases+=("${base}")
  done < <(workload_quadlet_sot_basenames "${sot_dir}")

  for base in "${new_bases[@]+"${new_bases[@]}"}"; do
    workload_unit_refuse_foreign_basename "${wl_name}" "${base}" "${prev_owned}" || return 1
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
      workload_unit_stop_basename "${consumer}" "${base}"
      rm -f "${dest_dir}/${base}"
    fi
  done

  for base in "${new_bases[@]+"${new_bases[@]}"}"; do
    install -m 0644 "${sot_dir}/${base}" "${dest_dir}/${base}"
    if [[ -n "${USER_NAME:-}" ]]; then
      chown "${USER_NAME}:${USER_NAME}" "${dest_dir}/${base}"
    fi
  done
}

# Reconcile both consumers after SoT sync.
# Args: wl_name prev_owned_file prev_quadlets_file prev_systemd_file
workload_unit_reconcile_dual() {
  local wl_name="$1"
  local prev_owned="$2"
  local prev_quadlets="$3"
  local prev_systemd="$4"
  workload_unit_reconcile_consumer "${wl_name}" quadlets "${UNIT_DIR}" "${prev_quadlets}" "${prev_owned}" || return 1
  workload_unit_reconcile_consumer "${wl_name}" systemd "${SYSTEMD_USER_DIR}" "${prev_systemd}" "${prev_owned}" || return 1
}

# Apply Intent for one authored unit by kind (Workload-wide Intent; no partial Intent).
# Args: consumer base sot_file intent
workload_unit_apply_basename_intent() {
  local consumer="$1"
  local base="$2"
  local file="$3"
  local intent="$4"
  local kind svc _
  kind="$(workload_unit_kind "${consumer}" "${base}" "${file}")"
  [[ -n "${kind}" ]] || return 0

  case "${consumer}" in
  quadlets) svc="$(workload_quadlet_service_name "${base}")" ;;
  systemd) svc="$(workload_systemd_unit_name "${base}")" ;;
  *) return 0 ;;
  esac
  [[ -n "${svc}" ]] || return 0

  quadlet_user systemctl --user reset-failed "${svc}" 2>/dev/null || true

  if [[ "${intent}" == "run" ]]; then
    case "${kind}" in
    always-on)
      quadlet_user systemctl --user restart "${svc}"
      for _ in $(seq 1 30); do
        if quadlet_user systemctl --user --quiet is-active "${svc}"; then
          break
        fi
        sleep 1
      done
      quadlet_user systemctl --user --quiet is-active "${svc}"
      ;;
    on-demand)
      case "${base##*.}" in
      timer)
        quadlet_user systemctl --user enable --now "${svc}"
        ;;
      *)
        # Armed: installed so a condition can fire; job payloads not started by Setup.
        :
        ;;
      esac
      ;;
    ensure)
      # Create/pull/build once. restart (not start): re-ensure after resource
      # removal while the oneshot remains active (exited).
      quadlet_user systemctl --user restart "${svc}"
      ;;
    esac
  else
    # stop / trash
    case "${kind}" in
    always-on)
      quadlet_user systemctl --user stop "${svc}" 2>/dev/null || true
      ;;
    on-demand)
      case "${base##*.}" in
      timer)
        quadlet_user systemctl --user disable --now "${svc}" 2>/dev/null || true
        ;;
      *)
        # Disarm: stop any in-flight job instance.
        quadlet_user systemctl --user stop "${svc}" 2>/dev/null || true
        ;;
      esac
      ;;
    ensure)
      # Leave Ensure resources in place; unit files retained until Purge.
      :
      ;;
    esac
  fi
}

# Apply Intent across both consumers for the Workload's current SoT.
# Kind order: Ensure, then Always-on, then On-demand (Arm last).
workload_unit_apply_intent() {
  local wl_name="$1"
  local intent="$2"
  local base sot kind consumer
  local -a ensure_args=()
  local -a always_args=()
  local -a ondemand_args=()
  local i

  for consumer in quadlets systemd; do
    sot="${WORKLOADS_ROOT}/${wl_name}/${consumer}"
    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      kind="$(workload_unit_kind "${consumer}" "${base}" "${sot}/${base}")"
      case "${kind}" in
      ensure) ensure_args+=("${consumer}" "${base}" "${sot}/${base}") ;;
      always-on) always_args+=("${consumer}" "${base}" "${sot}/${base}") ;;
      on-demand) ondemand_args+=("${consumer}" "${base}" "${sot}/${base}") ;;
      esac
    done < <(workload_quadlet_sot_basenames "${sot}")
  done

  for ((i = 0; i < ${#ensure_args[@]}; i += 3)); do
    workload_unit_apply_basename_intent \
      "${ensure_args[i]}" "${ensure_args[i + 1]}" "${ensure_args[i + 2]}" "${intent}"
  done
  for ((i = 0; i < ${#always_args[@]}; i += 3)); do
    workload_unit_apply_basename_intent \
      "${always_args[i]}" "${always_args[i + 1]}" "${always_args[i + 2]}" "${intent}"
  done
  for ((i = 0; i < ${#ondemand_args[@]}; i += 3)); do
    workload_unit_apply_basename_intent \
      "${ondemand_args[i]}" "${ondemand_args[i + 1]}" "${ondemand_args[i + 2]}" "${intent}"
  done
}
