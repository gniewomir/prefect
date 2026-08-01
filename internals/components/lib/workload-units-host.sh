#!/usr/bin/env bash
# Workload dual-consumer unit apply (sourced by Workload Setup).
# Validates staged consumers, syncs Host Volume SoT, reconciles Host unit dirs,
# optional before-reload hook, session reload, then applies Workload Intent.
#
# Public interface:
#   workload_units_apply wl_name intent quadlets_stage systemd_stage
#
# Optional ambient hook (caller-defined, unset after use):
#   workload_units_before_reload  — runs after reconcile, before daemon-reload
#                                   (Setup uses this for Environment Configuration)
#
# Requires ambient: WORKLOADS_ROOT, UNIT_DIR, SYSTEMD_USER_DIR, USER_NAME
# Assumes quadlet_user_session_begin already called (or dirs set for offline tests).

# shellcheck source=workload-quadlets-host.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workload-quadlets-host.sh"

# Apply dual-consumer units from staged dirs through Workload Intent.
# Args: wl_name intent quadlets_stage systemd_stage
# Performs: snapshot prev → validate → collision check → sync SoT both →
#           reconcile dual → optional before_reload hook → reload → Intent.
# Returns 0 on success.
workload_units_apply() {
  local wl_name="${1:?workload name required}"
  local intent="${2:?intent required}"
  local quadlets_stage="${3:-}"
  local systemd_stage="${4:-}"
  local prev_quadlets prev_systemd prev_owned stage_units
  local base

  case "${intent}" in
  run | stop | trash) ;;
  *)
    echo "workload_units_apply: intent must be run|stop|trash (got '${intent}')" >&2
    return 1
    ;;
  esac

  prev_quadlets="$(mktemp "${TMPDIR:-/tmp}/platform-prev-quadlets.XXXXXX")"
  prev_systemd="$(mktemp "${TMPDIR:-/tmp}/platform-prev-systemd.XXXXXX")"
  prev_owned="$(mktemp "${TMPDIR:-/tmp}/platform-prev-owned.XXXXXX")"
  stage_units="$(mktemp "${TMPDIR:-/tmp}/platform-stage-units.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '${prev_quadlets}' '${prev_systemd}' '${prev_owned}' '${stage_units}'" RETURN

  workload_quadlet_sot_basenames "${WORKLOADS_ROOT}/${wl_name}/quadlets" >"${prev_quadlets}" || true
  workload_quadlet_sot_basenames "${WORKLOADS_ROOT}/${wl_name}/systemd" >"${prev_systemd}" || true
  {
    cat "${prev_quadlets}"
    cat "${prev_systemd}"
  } | LC_ALL=C sort -u >"${prev_owned}"

  unit_validate_consumer_dir quadlets "${quadlets_stage}" || return 1
  unit_validate_consumer_dir systemd "${systemd_stage}" || return 1

  {
    workload_quadlet_sot_basenames "${quadlets_stage}"
    workload_quadlet_sot_basenames "${systemd_stage}"
  } | LC_ALL=C sort -u >"${stage_units}"

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    workload_unit_refuse_foreign_basename "${wl_name}" "${base}" "${prev_owned}" || return 1
  done <"${stage_units}"

  workload_unit_sync_sot "${wl_name}" quadlets "${quadlets_stage}" || return 1
  workload_unit_sync_sot "${wl_name}" systemd "${systemd_stage}" || return 1

  workload_unit_reconcile_dual "${wl_name}" "${prev_owned}" "${prev_quadlets}" "${prev_systemd}" || return 1

  if declare -F workload_units_before_reload >/dev/null 2>&1; then
    workload_units_before_reload || return 1
  fi

  quadlet_user_session_reload
  workload_unit_apply_intent "${wl_name}" "${intent}"
}
