#!/usr/bin/env bash
# Orphan Reap selection helpers (ADR-0041 / #156).
# Sourced by purge-orphans-host. Selection only — cleanup stays in the Host script.
#
# Public interface:
#   orphan_reap_absent_basenames WORKLOADS_ROOT KEEP_FILE
#     Prints sorted Host Workload basenames (manifest.json present) whose name is
#     not listed in KEEP_FILE (one basename per line). KEEP_FILE may be empty.

orphan_reap_absent_basenames() {
  local workloads_root="${1:?orphan_reap_absent_basenames requires WORKLOADS_ROOT}"
  local keep_file="${2:?orphan_reap_absent_basenames requires KEEP_FILE}"
  local wl_dir wl_name

  [[ -f "${keep_file}" ]] || {
    echo "orphan_reap_absent_basenames: keep file missing: ${keep_file}" >&2
    return 1
  }

  [[ -d "${workloads_root}" ]] || return 0

  for wl_dir in "${workloads_root}"/*; do
    [[ -d "${wl_dir}" && -f "${wl_dir}/manifest.json" ]] || continue
    wl_name="$(basename "${wl_dir}")"
    [[ "${wl_name}" != .* ]] || continue
    if grep -Fxq -- "${wl_name}" "${keep_file}"; then
      continue
    fi
    printf '%s\n' "${wl_name}"
  done | LC_ALL=C sort
}
