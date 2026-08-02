#!/usr/bin/env bash
# Unified test dispatcher (ADR-0036). Suites live under internals/test/<suite>/run.sh.
# Usage: ./test.sh <suite> [--verbose] [<case-selector>] [--env <slug>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="${REPO_ROOT}/internals/test"

usage() {
  cat <<EOF
Usage:
  ./test.sh <suite> [--verbose] [<case-selector>] [--env <slug>]
  ./test.sh <suite> [--verbose] [--env <slug>]

Suites (subdirectory of internals/test/):
  acceptance   Applied Stack external behavior (Host present; non-destructive)
  lifecycle    Park / Apply-after-Park / Teardown (destructive; opt-in)
  unit         Colocated *_test.sh under internals/ (no Applied Stack)

--verbose (or TEST_VERBOSE=1) streams each case live instead of quiet-on-pass.
--env is only valid for acceptance and lifecycle (ADR-0019). When present it must be last.
See docs/agents/testing.md.
EOF
}

fail_usage() {
  echo "FAIL: $*" >&2
  echo >&2
  usage >&2
  exit 1
}

if [[ $# -lt 1 ]]; then
  fail_usage "suite is required"
fi

SUITE="$1"
shift

case "${SUITE}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

SUITE_DIR="${TEST_ROOT}/${SUITE}"
RUN_SH="${SUITE_DIR}/run.sh"

if [[ ! -d "${SUITE_DIR}" || ! -f "${RUN_SH}" ]]; then
  fail_usage "unknown suite '${SUITE}' (expected a directory with run.sh under internals/test/)"
fi

# Remaining argv as a Bash-3.2-safe array (no negative offsets).
REST=("$@")
N=${#REST[@]}
ENV_ARGS=()

if [[ "${N}" -ge 2 ]]; then
  idx_env=$((N - 2))
  idx_slug=$((N - 1))
  if [[ "${REST[idx_env]}" == "--env" ]]; then
    ENV_SLUG="${REST[idx_slug]}"
    if [[ -z "${ENV_SLUG}" || "${ENV_SLUG}" == --* ]]; then
      fail_usage "--env requires a slug"
    fi
    ENV_ARGS=(--env "${ENV_SLUG}")
    if [[ "${idx_env}" -eq 0 ]]; then
      REST=()
    else
      REST=("${REST[@]:0:idx_env}")
    fi
    N=${#REST[@]}
  fi
fi

if [[ "${N}" -ge 1 ]]; then
  idx_last=$((N - 1))
  last="${REST[idx_last]}"
  if [[ "${last}" == "--env" || "${last}" == --env=* ]]; then
    fail_usage "--env requires a slug and must be last as: --env <slug>"
  fi
fi

# Reject --env appearing anywhere else in the remaining argv.
for arg in "${REST[@]+"${REST[@]}"}"; do
  if [[ "${arg}" == --env || "${arg}" == --env=* ]]; then
    fail_usage "--env must be last when present"
  fi
done

# Optional --verbose anywhere before --env; export for suite runners / run_buffered_case.
VERBOSE=0
FILTERED=()
for arg in "${REST[@]+"${REST[@]}"}"; do
  case "${arg}" in
    --verbose)
      VERBOSE=1
      ;;
    -*)
      fail_usage "unknown flag '${arg}'"
      ;;
    *)
      FILTERED+=("${arg}")
      ;;
  esac
done
REST=("${FILTERED[@]+"${FILTERED[@]}"}")
N=${#REST[@]}

if [[ "${VERBOSE}" -eq 1 ]]; then
  export TEST_VERBOSE=1
fi

if [[ "${N}" -gt 1 ]]; then
  fail_usage "too many arguments after suite (expected optional case-selector only)"
fi

SELECTOR_ARGS=()
if [[ "${N}" -eq 1 ]]; then
  SELECTOR_ARGS=("${REST[0]}")
fi

if [[ ${#ENV_ARGS[@]} -gt 0 && "${SUITE}" == "unit" ]]; then
  fail_usage "--env is not valid for suite 'unit'"
fi

exec bash "${RUN_SH}" \
  ${SELECTOR_ARGS[@]+"${SELECTOR_ARGS[@]}"} \
  ${ENV_ARGS[@]+"${ENV_ARGS[@]}"}
