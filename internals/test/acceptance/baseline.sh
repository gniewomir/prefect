#!/usr/bin/env bash
# Acceptance suite baseline helpers (ADR-0042 / #162).
# Sourced by run.sh and baseline_test.sh — not an operator entrypoint.
# Requires: PLATFORM_ENV (after environment_activate); REPO_ROOT for Deploy baseline.

# Suite-start acknowledgement for non-test Environments (diagnostic Acceptance).
# test (including default alias → PLATFORM_ENV=test) skips the prompt.
acceptance_confirm_diagnose() {
  local env_slug="${PLATFORM_ENV:?acceptance_confirm_diagnose: PLATFORM_ENV required}"
  if [[ "${env_slug}" == "test" ]]; then
    return 0
  fi
  echo "WARNING: Acceptance on non-test Environment '${env_slug}' is diagnostic."
  echo "         No Environment fixtures / Intent flips that imply undeclared Host"
  echo "         data loss. Runner still Deploy-converges before each case (ADR-0042)."
  echo
  printf "Type exactly 'diagnose %s' to run Acceptance Tests: " "${env_slug}"
  local confirm
  read -r confirm
  if [[ "${confirm}" != "diagnose ${env_slug}" ]]; then
    echo "FAIL: aborted (expected exact 'diagnose ${env_slug}')" >&2
    return 1
  fi
  echo
}

# Bring the Host to Deployed using the existing Deploy ladder path (ensure.sh).
# Failed cases leave Host dirty until the next call (ADR-0042).
acceptance_baseline_deployed() {
  local root="${REPO_ROOT:?acceptance_baseline_deployed: REPO_ROOT required}"
  local env_slug="${PLATFORM_ENV:?acceptance_baseline_deployed: PLATFORM_ENV required}"
  "${root}/internals/ensure.sh" --env "${env_slug}"
}
