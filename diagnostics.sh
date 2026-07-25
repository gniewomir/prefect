#!/usr/bin/env bash
# Pull Host diagnostics for an Environment (named artifact bundles) for local inspection.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Bundle: omitted / --bundle ihp → Initial Host Provisioning evidence (logs + status --long).
# Output: omitted → $TMPDIR/prefect-diagnostics-<env>-<bundle>-<timestamp>/; or --out <dir>.
# Requires: terraform, ssh; applied State with a live Host (Reserved IP assigned).
# Optional: SSH_IDENTITY=/path/to/private_key (defaults to ssh agent / default identities).
# Usage: ./diagnostics.sh [--env <slug>] [--bundle <id>] [--out <dir>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=lib/diagnostics.sh
source "${REPO_ROOT}/lib/diagnostics.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"
diagnostics_parse_args "$@" || exit 1

BUNDLE="$(diagnostics_bundle_or_default "${DIAGNOSTICS_BUNDLE_RAW}")" || exit 1
ENV_SLUG="${PREFECT_ENV}"

command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

cd "${STACK_DIR}"

IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (apply the Stack first — Host diagnostics need a live Host)"

OUT_DIR="${DIAGNOSTICS_OUT}"
if [[ -z "${OUT_DIR}" ]]; then
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  OUT_DIR="${TMPDIR:-/tmp}/prefect-diagnostics-${ENV_SLUG}-${BUNDLE}-${ts}"
fi
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=2
  -o StrictHostKeyChecking=accept-new
)
if [[ -n "${SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

# Probe: Host must answer (fail closed — Parked / unreachable is not an empty tarball).
if ! ssh "${SSH_OPTS[@]}" "root@${IP}" "true" 2>/dev/null; then
  fail "Host at ${IP} not reachable over SSH (Parked, never Applied, or SSH auth failed)"
fi

STATUS_NAME="$(diagnostics_bundle_status_snapshot "${BUNDLE}")"
got=0
missing=""

# Best-effort: copy each log file by basename via a short remote cat (skip if absent).
while IFS= read -r remote_path; do
  [[ -n "${remote_path}" ]] || continue
  base="$(basename "${remote_path}")"
  local_path="${OUT_DIR}/${base}"
  if ssh "${SSH_OPTS[@]}" "root@${IP}" \
    "test -f $(printf '%q' "${remote_path}") && cat $(printf '%q' "${remote_path}")" \
    >"${local_path}" 2>/dev/null && [[ -f "${local_path}" ]]; then
    got=$((got + 1))
  else
    rm -f "${local_path}"
    missing="${missing} ${base}"
  fi
done < <(diagnostics_bundle_log_files "${BUNDLE}")

if [[ -n "${STATUS_NAME}" ]]; then
  status_out="${OUT_DIR}/${STATUS_NAME}"
  if ssh "${SSH_OPTS[@]}" "root@${IP}" "command -v cloud-init >/dev/null"; then
    set +e
    ssh "${SSH_OPTS[@]}" "root@${IP}" "cloud-init status --long" >"${status_out}" 2>&1
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
