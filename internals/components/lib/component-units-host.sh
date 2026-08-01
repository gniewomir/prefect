#!/usr/bin/env bash
# Component dual-consumer unit install (sourced by Component Setup).
# Installs authored quadlets/ → UNIT_DIR and systemd/ → SYSTEMD_USER_DIR.
# Wrong-folder authorship fails closed. No Workload Intent / SoT ownership.
#
# Expects after quadlet_user_session_begin: UNIT_DIR, SYSTEMD_USER_DIR.
# Optional: USER_NAME for soft-fail chown (offline tests / non-root).

# shellcheck source=unit-consumers-host.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unit-consumers-host.sh"

# Install regular files from one consumer stage into the mapped Host dir.
# Args: consumer (quadlets|systemd) stage_dir
component_units_install_consumer() {
  local consumer="$1"
  local stage_dir="${2:-}"
  local dest src base
  dest="$(unit_consumer_dest_dir "${consumer}")" || return 1
  mkdir -p "${dest}"
  [[ -n "${stage_dir}" && -d "${stage_dir}" ]] || return 0
  for src in "${stage_dir}"/*; do
    [[ -f "${src}" ]] || continue
    base="$(basename "${src}")"
    [[ "${base}" == .* ]] && continue
    install -m 0644 "${src}" "${dest}/${base}"
    if [[ -n "${USER_NAME:-}" ]]; then
      chown "${USER_NAME}:${USER_NAME}" "${dest}/${base}" 2>/dev/null || true
    fi
  done
}

# Validate + install both consumers from a Component tree.
# Args: component_tree (directory containing optional quadlets/ and systemd/)
component_units_install() {
  local tree="${1:?component tree required}"
  local quadlets_dir="${tree}/quadlets"
  local systemd_dir="${tree}/systemd"

  unit_validate_consumer_dir quadlets "${quadlets_dir}" || return 1
  unit_validate_consumer_dir systemd "${systemd_dir}" || return 1
  component_units_install_consumer quadlets "${quadlets_dir}" || return 1
  component_units_install_consumer systemd "${systemd_dir}" || return 1
}
