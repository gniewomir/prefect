#!/usr/bin/env bash
# Pull Host diagnostics for an Environment (named artifact bundles) for local inspection.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Bundle: required --bundle <id> (v1: ihp — Initial Host Provisioning evidence).
# Output: omitted → $TMPDIR/prefect-diagnostics-<env>-<bundle>-<timestamp>/; or --out <dir>.
# Requires: terraform, ssh; applied State with a live Host (Reserved IP assigned).
# Optional: SSH_IDENTITY=/path/to/private_key (defaults to ssh agent / default identities).
# Usage: ./diagnostics.sh [--env <slug>] --bundle <id> [--out <dir>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=lib/diagnostics.sh
source "${REPO_ROOT}/lib/diagnostics.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"
diagnostics_parse_args "$@" || exit 1

if [[ -z "${DIAGNOSTICS_BUNDLE_RAW}" ]]; then
  diagnostics_usage
  echo >&2
  fail "--bundle is required"
fi

BUNDLE="$(diagnostics_resolve_bundle "${DIAGNOSTICS_BUNDLE_RAW}")" || exit 1
ENV_SLUG="${PREFECT_ENV}"

command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

host_session_open operator "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

OUT_DIR="${DIAGNOSTICS_OUT}"
if [[ -z "${OUT_DIR}" ]]; then
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  OUT_DIR="${TMPDIR:-/tmp}/prefect-diagnostics-${ENV_SLUG}-${BUNDLE}-${ts}"
fi
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

# Probe: Host must answer (fail closed — Parked / unreachable is not an empty tarball).
if ! host_ssh "true" 2>/dev/null; then
  fail "Host at ${IP} not reachable over SSH (Parked, never Applied, or SSH auth failed)"
fi

STATUS_NAME="$(diagnostics_bundle_status_snapshot "${BUNDLE}")"
got=0
missing=""

# Best-effort: copy each log file by basename via a short remote cat (skip if absent).
# </dev/null: do not steal stdin from the while-read process substitution (would drop paths).
while IFS= read -r remote_path; do
  [[ -n "${remote_path}" ]] || continue
  base="$(basename "${remote_path}")"
  local_path="${OUT_DIR}/${base}"
  if host_ssh \
    "test -f $(printf '%q' "${remote_path}") && cat $(printf '%q' "${remote_path}")" \
    </dev/null >"${local_path}" 2>/dev/null && [[ -f "${local_path}" ]]; then
    got=$((got + 1))
  else
    rm -f "${local_path}"
    missing="${missing} ${base}"
  fi
done < <(diagnostics_bundle_log_files "${BUNDLE}")

if [[ -n "${STATUS_NAME}" ]]; then
  status_out="${OUT_DIR}/${STATUS_NAME}"
  if host_ssh "command -v cloud-init >/dev/null" </dev/null; then
    set +e
    host_ssh "cloud-init status --long" </dev/null >"${status_out}" 2>&1
    status_rc=$?
    set -e
    if [[ -s "${status_out}" ]]; then
      got=$((got + 1))
      if [[ "${status_rc}" -ne 0 ]]; then
        echo "WARNING: cloud-init status --long exited ${status_rc}; saved output to ${STATUS_NAME}" >&2
      fi
    else
      rm -f "${status_out}"
      missing="${missing} ${STATUS_NAME}"
      echo "WARNING: cloud-init status --long produced no output" >&2
    fi
  else
    rm -f "${status_out}"
    missing="${missing} ${STATUS_NAME}"
    echo "WARNING: cloud-init unavailable on Host" >&2
  fi
fi

missing="${missing# }"
if [[ -n "${missing}" ]]; then
  echo "WARNING: missing artifacts: ${missing}" >&2
fi

if [[ "${got}" -eq 0 ]]; then
  fail "no Host diagnostics artifacts retrieved for bundle '${BUNDLE}'"
fi

echo "${OUT_DIR}"
