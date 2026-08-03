#!/usr/bin/env bash
# Environment Workload discovery (ADR-0041 / #156).
# Discovers Workload definition trees under an Environment directory by presence of
# manifest.json on immediate children. Does not validate Manifest content.
#
# Public interface:
#   environment_discover_workloads ENV_DIR
#     Prints sorted basenames (one per line). Empty when none.

environment_discover_workloads() {
  local env_dir="${1:?environment_discover_workloads requires ENV_DIR}"
  local child name

  [[ -d "${env_dir}" ]] || {
    echo "environment_discover_workloads: not a directory: ${env_dir}" >&2
    return 1
  }

  for child in "${env_dir}"/*; do
    [[ -d "${child}" ]] || continue
    name="$(basename "${child}")"
    [[ "${name}" != .* ]] || continue
    [[ -f "${child}/manifest.json" ]] || continue
    printf '%s\n' "${name}"
  done | LC_ALL=C sort
}
