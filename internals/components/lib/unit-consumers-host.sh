#!/usr/bin/env bash
# Dual-consumer unit authorship helpers (sourced by Component and Workload Host libs).
# Consumers: quadlets/ → UNIT_DIR; systemd/ → SYSTEMD_USER_DIR (ADR-0034).
# Wrong-folder authoring fails closed. No Intent / SoT ownership here.

# True when extension belongs under authored quadlets/.
unit_ext_is_quadlet() {
  case "$1" in
  container | pod | kube | network | volume | image | build | artifact) return 0 ;;
  *) return 1 ;;
  esac
}

# True when extension belongs under authored systemd/.
unit_ext_is_native() {
  case "$1" in
  service | timer | socket | path | target | slice | mount | automount | swap) return 0 ;;
  *) return 1 ;;
  esac
}

# Host destination for one consumer (requires UNIT_DIR / SYSTEMD_USER_DIR).
# Args: consumer (quadlets|systemd)
unit_consumer_dest_dir() {
  local consumer="$1"
  case "${consumer}" in
  quadlets)
    printf '%s\n' "${UNIT_DIR}"
    ;;
  systemd)
    printf '%s\n' "${SYSTEMD_USER_DIR}"
    ;;
  *)
    echo "unit_consumer_dest_dir: unknown consumer '${consumer}'" >&2
    return 1
    ;;
  esac
}

# Fail closed if any regular file in stage_dir has the wrong consumer extension.
# Args: consumer (quadlets|systemd) stage_dir (may be missing/empty — valid)
unit_validate_consumer_dir() {
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
      echo "unit ${consumer}/ file '${base}' has no extension (wrong-folder / invalid unit)" >&2
      return 1
    fi
    case "${consumer}" in
    quadlets)
      if unit_ext_is_quadlet "${ext}"; then
        continue
      fi
      if unit_ext_is_native "${ext}"; then
        echo "unit '${base}' authored under quadlets/ but belongs in systemd/ (wrong-folder)" >&2
        return 1
      fi
      echo "unit quadlets/ file '${base}' has unsupported extension '.${ext}'" >&2
      return 1
      ;;
    systemd)
      if unit_ext_is_native "${ext}"; then
        continue
      fi
      if unit_ext_is_quadlet "${ext}"; then
        echo "unit '${base}' authored under systemd/ but belongs in quadlets/ (wrong-folder)" >&2
        return 1
      fi
      echo "unit systemd/ file '${base}' has unsupported extension '.${ext}'" >&2
      return 1
      ;;
    *)
      echo "unit_validate_consumer_dir: unknown consumer '${consumer}'" >&2
      return 1
      ;;
    esac
  done
}
