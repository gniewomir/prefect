#!/usr/bin/env bash
# Workload dual-consumer unit apply (sourced by Workload Setup).
# Validates staged consumers, syncs Host Volume SoT, reconciles Host unit dirs,
# optional before-reload hook, session reload, then applies Workload Intent.
#
# Public interface:
#   workload_units_preflight wl_name quadlets_stage systemd_stage
#   workload_units_apply wl_name intent quadlets_stage systemd_stage
#   workload_units_purge wl_name
#
# Optional ambient hook (caller-defined, unset after use):
#   workload_units_before_reload  — runs after reconcile, before daemon-reload
#                                   (Setup uses this for Environment Configuration)
#
# Requires ambient: WORKLOADS_ROOT, UNIT_DIR, SYSTEMD_USER_DIR, USER_NAME
# Assumes quadlet_user_session_begin already called (or dirs set for offline tests).

# shellcheck source=workload-quadlets-host.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workload-quadlets-host.sh"

# Fail closed on wrong-folder authorship and foreign basename ownership.
# Does not mutate Host Volume SoT or Host unit dirs — call before other Setup writes.
# Args: wl_name quadlets_stage systemd_stage
workload_units_preflight() {
  local wl_name="${1:?workload name required}"
  local quadlets_stage="${2:-}"
  local systemd_stage="${3:-}"
  local prev_quadlets prev_systemd prev_owned stage_units
  local base
  local rc=0

  prev_quadlets="$(mktemp "${TMPDIR:-/tmp}/platform-prev-quadlets.XXXXXX")"
  prev_systemd="$(mktemp "${TMPDIR:-/tmp}/platform-prev-systemd.XXXXXX")"
  prev_owned="$(mktemp "${TMPDIR:-/tmp}/platform-prev-owned.XXXXXX")"
  stage_units="$(mktemp "${TMPDIR:-/tmp}/platform-stage-units.XXXXXX")"

  workload_quadlet_sot_basenames "${WORKLOADS_ROOT}/${wl_name}/quadlets" >"${prev_quadlets}" || true
  workload_quadlet_sot_basenames "${WORKLOADS_ROOT}/${wl_name}/systemd" >"${prev_systemd}" || true
  {
    cat "${prev_quadlets}"
    cat "${prev_systemd}"
  } | LC_ALL=C sort -u >"${prev_owned}"

  if ! unit_validate_consumer_dir quadlets "${quadlets_stage}"; then
    rc=1
  elif ! unit_validate_consumer_dir systemd "${systemd_stage}"; then
    rc=1
  else
    {
      workload_quadlet_sot_basenames "${quadlets_stage}"
      workload_quadlet_sot_basenames "${systemd_stage}"
    } | LC_ALL=C sort -u >"${stage_units}"

    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      if ! workload_unit_refuse_foreign_basename "${wl_name}" "${base}" "${prev_owned}"; then
        rc=1
        break
      fi
    done <"${stage_units}"
  fi

  rm -f "${prev_quadlets}" "${prev_systemd}" "${prev_owned}" "${stage_units}"
  return "${rc}"
}

# Apply dual-consumer units from staged dirs through Workload Intent.
# Args: wl_name intent quadlets_stage systemd_stage
# Performs: preflight → sync SoT both → reconcile dual → optional before_reload
#           hook → reload → Intent.
# Returns 0 on success.
workload_units_apply() {
  local wl_name="${1:?workload name required}"
  local intent="${2:?intent required}"
  local quadlets_stage="${3:-}"
  local systemd_stage="${4:-}"
  local prev_quadlets prev_systemd prev_owned
  local rc=0

  case "${intent}" in
  run | stop | trash) ;;
  *)
    echo "workload_units_apply: intent must be run|stop|trash (got '${intent}')" >&2
    return 1
    ;;
  esac

  workload_units_preflight "${wl_name}" "${quadlets_stage}" "${systemd_stage}" || return 1

  prev_quadlets="$(mktemp "${TMPDIR:-/tmp}/platform-prev-quadlets.XXXXXX")"
  prev_systemd="$(mktemp "${TMPDIR:-/tmp}/platform-prev-systemd.XXXXXX")"
  prev_owned="$(mktemp "${TMPDIR:-/tmp}/platform-prev-owned.XXXXXX")"

  workload_quadlet_sot_basenames "${WORKLOADS_ROOT}/${wl_name}/quadlets" >"${prev_quadlets}" || true
  workload_quadlet_sot_basenames "${WORKLOADS_ROOT}/${wl_name}/systemd" >"${prev_systemd}" || true
  {
    cat "${prev_quadlets}"
    cat "${prev_systemd}"
  } | LC_ALL=C sort -u >"${prev_owned}"

  if ! workload_unit_sync_sot "${wl_name}" quadlets "${quadlets_stage}"; then
    rc=1
  elif ! workload_unit_sync_sot "${wl_name}" systemd "${systemd_stage}"; then
    rc=1
  elif ! workload_unit_reconcile_dual "${wl_name}" "${prev_owned}" "${prev_quadlets}" "${prev_systemd}"; then
    rc=1
  else
    if declare -F workload_units_before_reload >/dev/null 2>&1; then
      if ! workload_units_before_reload; then
        rc=1
      fi
    fi
    if [[ "${rc}" -eq 0 ]]; then
      quadlet_user_session_reload
      if ! workload_unit_apply_intent "${wl_name}" "${intent}"; then
        rc=1
      fi
    fi
  fi

  rm -f "${prev_quadlets}" "${prev_systemd}" "${prev_owned}"
  return "${rc}"
}

# Tear down Host unit files + Setup-owned drop-in dirs for one Workload's SoT basenames.
# Args: wl_name
# Reads SoT under WORKLOADS_ROOT/wl_name/{quadlets,systemd}
# For each basename in both consumers: stop (best-effort), rm unit file, rm unit.d drop-in dir.
# Does NOT remove Host Volume Workload tree, Routes, or Environment Configuration.
workload_units_purge() {
  local wl_name="${1:?workload name required}"
  local base
  local wl_dir="${WORKLOADS_ROOT}/${wl_name}"

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
}
