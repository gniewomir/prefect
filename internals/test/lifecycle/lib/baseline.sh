#!/usr/bin/env bash
# Lifecycle suite baseline helpers (ADR-0042 / #161 / #165).
# Sourced by run.sh and baseline_test.sh — not an operator entrypoint.
# Requires: PLATFORM_ENV (after environment_activate); REPO_ROOT for Teardown baseline.

# Fail closed unless the active Environment is the test cloud slug.
# After environment_activate, omitted / default / test all yield PLATFORM_ENV=test.
lifecycle_require_test_environment() {
  if [[ "${PLATFORM_ENV:-}" != "test" ]]; then
    echo "FAIL: Lifecycle Tests are test-Environment only (got --env '${PLATFORM_ENV:-}'; ADR-0042)" >&2
    return 1
  fi
}

# Suite-start acknowledgement: every Lifecycle invocation wipes Durables between cases.
lifecycle_confirm_suite_teardown() {
  echo "WARNING: Lifecycle suite baselines to Stack absent via Teardown before each case"
  echo "         (full wipe including Durables). Billing for Reserved IP, Host Volume,"
  echo "         and Domain stops during Teardown. Slow by design (ADR-0042)."
  echo
  printf "Type exactly 'teardown' to run Lifecycle Tests: "
  local confirm
  read -r confirm
  if [[ "${confirm}" != "teardown" ]]; then
    echo "FAIL: aborted (expected exact 'teardown')" >&2
    return 1
  fi
  echo
}

# Bring the Stack to absent using the existing Teardown operator path, and drop
# Environment Domain override residue that survives Teardown (ADR-0021 / #165).
# Pipes the nested teardown.sh confirm (suite confirm already happened once).
lifecycle_baseline_stack_absent() {
  local root="${REPO_ROOT:?lifecycle_baseline_stack_absent: REPO_ROOT required}"
  local env_slug="${PLATFORM_ENV:?lifecycle_baseline_stack_absent: PLATFORM_ENV required}"
  rm -f "${root}/environments/${env_slug}/domains.override.json"
  printf 'teardown\n' | "${root}/teardown.sh" --env "${env_slug}"
}
