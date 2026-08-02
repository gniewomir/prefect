#!/usr/bin/env bash
# Buffered test-case runner: print --- label ---, spin while the case runs with
# stdout+stderr captured; dump the log only on failure. Sourced by suite run.sh.
# Set TEST_VERBOSE=1 (or pass --verbose to ./test.sh) to stream case output live.

# Usage: run_buffered_case <label> <case_path>
# Returns the case's exit status. Spinner only when stderr is a TTY (quiet mode).
run_buffered_case() {
  local label="$1"
  local case_path="$2"
  local log pid rc i frame
  local spin_chars='|/-\'

  printf '%s\n' "--- ${label} ---"

  if [[ "${TEST_VERBOSE:-}" == "1" ]]; then
    set +e
    bash "${case_path}"
    rc=$?
    set -e
    return "${rc}"
  fi

  log="$(mktemp "${TMPDIR:-/tmp}/propraetor-test-case.XXXXXX")" || return 1

  bash "${case_path}" >"${log}" 2>&1 &
  pid=$!

  # Propagate interrupt to the case; clear on normal completion.
  # shellcheck disable=SC2064  # expand pid/log now for this case
  trap "kill '${pid}' 2>/dev/null || true; rm -f '${log}'; trap - INT TERM; exit 130" INT TERM

  i=0
  if [[ -t 2 ]]; then
    while kill -0 "${pid}" 2>/dev/null; do
      frame="${spin_chars:$((i % 4)):1}"
      printf '\r[%s] ' "${frame}" >&2
      i=$((i + 1))
      sleep 0.1
    done
    # Clear spinner glyphs (CSI K = erase to end of line).
    printf '\r\033[K' >&2
  fi

  set +e
  wait "${pid}"
  rc=$?
  set -e

  trap - INT TERM

  if [[ ${rc} -eq 0 ]]; then
    rm -f "${log}"
    return 0
  fi

  cat "${log}"
  rm -f "${log}"
  return "${rc}"
}
