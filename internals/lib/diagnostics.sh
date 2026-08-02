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
Usage: ./internals/diagnostics.sh --bundle <id> [--env <slug>] [--out <dir>]

Pull Host diagnostics (named artifact bundles) for local inspection.

  --bundle <id>    Required. Artifact bundle to pull
  --env <slug>     Environment (omitted / default / test → test)
  --out <dir>      Output directory (default: $TMPDIR/platform-diagnostics-<env>-<bundle>-<timestamp>/)

Bundles:
  ihp    Initial Host Provisioning evidence (cloud-init logs + status --long)

Requires: PROPRAETOR_PRIVATE_KEY_PATH (Operator Configuration)
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

