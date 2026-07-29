#!/usr/bin/env bash
# Host diagnostics helpers: bundle registry + closed argv for diagnostics.sh.
# Sourced by diagnostics.sh and lib/diagnostics_test.sh.

# Print known bundle ids (one per line). Keep in sync with resolve / artifact helpers.
diagnostics_known_bundles() {
  printf '%s\n' "ihp"
}

# Usage / help for the diagnostics operator entrypoint (stderr).
diagnostics_usage() {
  cat <<'EOF' >&2
Usage: ./internals/diagnostics.sh [--env <slug>] --bundle <id> [--out <dir>]

Pull Host diagnostics (named artifact bundles) for local inspection.

  --env <slug>     Environment (omitted / default / test → test)
  --bundle <id>    Required. Artifact bundle to pull
  --out <dir>      Output directory (default: $TMPDIR/platform-diagnostics-<env>-<bundle>-<timestamp>/)

Bundles:
  ihp    Initial Host Provisioning evidence (cloud-init logs + status --long)

Optional: SSH_IDENTITY=/path/to/private_key
EOF
}

# Resolve a required bundle id. Fails closed on empty or unknown.
diagnostics_resolve_bundle() {
  local id="${1-}"
  if [[ -z "${id}" ]]; then
    echo "FAIL: --bundle is required" >&2
    return 1
  fi
  case "${id}" in
    ihp)
      printf '%s\n' "ihp"
      return 0
      ;;
    *)
      echo "FAIL: unknown Host diagnostics bundle '${id}' (known: $(diagnostics_known_bundles | tr '\n' ' ' | sed 's/[[:space:]]*$//'))" >&2
      return 1
      ;;
  esac
}

# Remote log file paths for a registered bundle (one path per line).
diagnostics_bundle_log_files() {
  local id
  id="$(diagnostics_resolve_bundle "${1-}")" || return 1
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
  id="$(diagnostics_resolve_bundle "${1-}")" || return 1
  case "${id}" in
    ihp)
      printf '%s\n' "cloud-init-status-long.txt"
      ;;
  esac
}

# Parse argv for required --bundle and optional --out (closed surface).
# Sets DIAGNOSTICS_BUNDLE_RAW and DIAGNOSTICS_OUT.
# Does not require --bundle by itself — caller checks and prints usage.
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
        echo "FAIL: unknown argument: $1 (only optional --env, required --bundle, and optional --out are accepted)" >&2
        return 1
        ;;
    esac
  done
}
