#!/usr/bin/env bash
# Host diagnostics helpers: bundle registry + closed argv for diagnostics.sh.
# Sourced by diagnostics.sh and lib/diagnostics_test.sh.

# Resolve a bundle id (or empty) to a registered id. Fails closed on unknown.
diagnostics_bundle_or_default() {
  local raw="${1-}"
  local id="${raw:-ihp}"
  case "${id}" in
    ihp)
      printf '%s\n' "ihp"
      return 0
      ;;
    *)
      echo "FAIL: unknown Host diagnostics bundle '${id}' (known: ihp)" >&2
      return 1
      ;;
  esac
}

# Remote log file paths for a registered bundle (one path per line).
diagnostics_bundle_log_files() {
  local id
  id="$(diagnostics_bundle_or_default "${1-}")" || return 1
  case "${id}" in
    ihp)
      printf '%s\n' "/var/log/cloud-init-output.log"
      printf '%s\n' "/var/log/cloud-init.log"
      ;;
  esac
}

# Local basename for a command-snapshot artifact, if the bundle includes one.
# Empty stdout means no snapshot for that bundle.
diagnostics_bundle_status_snapshot() {
  local id
  id="$(diagnostics_bundle_or_default "${1-}")" || return 1
  case "${id}" in
    ihp)
      printf '%s\n' "cloud-init-status-long.txt"
      ;;
  esac
}

# Parse argv for optional --bundle / --out (closed surface).
# Sets DIAGNOSTICS_BUNDLE_RAW and DIAGNOSTICS_OUT.
diagnostics_parse_args() {
  DIAGNOSTICS_BUNDLE_RAW=""
  DIAGNOSTICS_OUT=""
  local seen_bundle=false
  local seen_out=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle)
        if [[ "${seen_bundle}" == true ]]; then
          echo "FAIL: duplicate --bundle (specify bundle once)" >&2
          return 1
        fi
        if [[ $# -lt 2 ]]; then
          echo "FAIL: --bundle requires an id (e.g. --bundle ihp)" >&2
          return 1
        fi
        DIAGNOSTICS_BUNDLE_RAW="$2"
        seen_bundle=true
        shift 2
        ;;
      --bundle=*)
        if [[ "${seen_bundle}" == true ]]; then
          echo "FAIL: duplicate --bundle (specify bundle once)" >&2
          return 1
        fi
        DIAGNOSTICS_BUNDLE_RAW="${1#--bundle=}"
        if [[ -z "${DIAGNOSTICS_BUNDLE_RAW}" ]]; then
          echo "FAIL: --bundle requires an id (e.g. --bundle=ihp)" >&2
          return 1
        fi
        seen_bundle=true
        shift
        ;;
      --out)
        if [[ "${seen_out}" == true ]]; then
          echo "FAIL: duplicate --out (specify output directory once)" >&2
          return 1
        fi
        if [[ $# -lt 2 ]]; then
          echo "FAIL: --out requires a directory path" >&2
          return 1
        fi
        DIAGNOSTICS_OUT="$2"
        seen_out=true
        shift 2
        ;;
      --out=*)
        if [[ "${seen_out}" == true ]]; then
          echo "FAIL: duplicate --out (specify output directory once)" >&2
          return 1
        fi
        DIAGNOSTICS_OUT="${1#--out=}"
        if [[ -z "${DIAGNOSTICS_OUT}" ]]; then
          echo "FAIL: --out requires a directory path" >&2
          return 1
        fi
        seen_out=true
        shift
        ;;
      *)
        echo "FAIL: unknown argument: $1 (only optional --env, --bundle, and --out are accepted)" >&2
        return 1
        ;;
    esac
  done
}
