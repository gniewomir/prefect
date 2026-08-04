#!/usr/bin/env bash
# Acceptance suite baseline helpers (ADR-0042 / #162 / #176).
# Sourced by run.sh and baseline_test.sh — not an operator entrypoint.
# Requires: PLATFORM_ENV (after environment_activate); REPO_ROOT for Deploy baseline.

# Fixture-class: case script references Environment fixture / SoT track helpers (#176).
acceptance_case_is_fixture_class() {
  local path="${1:?acceptance_case_is_fixture_class: case path required}"
  grep -qE 'acceptance_wl_track|acceptance_sot_track' "${path}"
}

# On non-test, drop fixture-class paths from a full-suite run (print skip lines to stderr).
# On test, print all paths unchanged. Paths are printed one per stdout line.
acceptance_filter_diagnose_cases() {
  local path base
  local env_slug="${PLATFORM_ENV:?acceptance_filter_diagnose_cases: PLATFORM_ENV required}"
  for path in "$@"; do
    if [[ "${env_slug}" != "test" ]] && acceptance_case_is_fixture_class "${path}"; then
      base="$(basename "${path}")"
      echo "SKIP: ${base} (fixture-class; diagnostic Acceptance keeps Environment SoT at HEAD — ADR-0042)" >&2
      continue
    fi
    printf '%s\n' "${path}"
  done
}

# Explicit selector on non-test: fixture-class case must refuse (not skip-as-pass).
acceptance_refuse_if_diagnose_fixture_selector() {
  local path="${1:?acceptance_refuse_if_diagnose_fixture_selector: case path required}"
  local env_slug="${PLATFORM_ENV:?acceptance_refuse_if_diagnose_fixture_selector: PLATFORM_ENV required}"
  local base
  if [[ "${env_slug}" == "test" ]]; then
    return 0
  fi
  if acceptance_case_is_fixture_class "${path}"; then
    base="$(basename "${path}")"
    echo "FAIL: ${base} mutates Environment SoT (fixture-class) — not allowed on non-test diagnostic Acceptance (ADR-0042)" >&2
    return 1
  fi
}

# Suite-start acknowledgement for non-test Environments (diagnostic Acceptance).
# test (including default alias → PLATFORM_ENV=test) skips the prompt.
acceptance_confirm_diagnose() {
  local env_slug="${PLATFORM_ENV:?acceptance_confirm_diagnose: PLATFORM_ENV required}"
  if [[ "${env_slug}" == "test" ]]; then
    return 0
  fi
  echo "WARNING: Acceptance on non-test Environment '${env_slug}' is diagnostic."
  echo "         Environment SoT stays at committed HEAD (no fixtures / SoT mutation)."
  echo "         Runner still Deploy-converges before each case (ADR-0042)."
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

# Non-test baseline Deploy requires Environment SoT at committed HEAD (ADR-0042 / #176).
acceptance_require_env_tree_at_head() {
  local root="${REPO_ROOT:?acceptance_require_env_tree_at_head: REPO_ROOT required}"
  local env_slug="${PLATFORM_ENV:?acceptance_require_env_tree_at_head: PLATFORM_ENV required}"
  local porcelain=""
  local status=0
  if [[ "${env_slug}" == "test" ]]; then
    return 0
  fi
  porcelain="$(git -C "${root}" status --porcelain --untracked-files=normal -- "environments/${env_slug}" 2>&1)" || status=$?
  if [[ "${status}" -ne 0 ]]; then
    echo "FAIL: cannot inspect Environment '${env_slug}' tree vs HEAD (git status failed; ADR-0042):" >&2
    printf '%s\n' "${porcelain}" >&2
    return 1
  fi
  if [[ -n "${porcelain}" ]]; then
    echo "FAIL: Environment '${env_slug}' tree differs from HEAD — diagnostic Acceptance requires committed SoT (ADR-0042):" >&2
    printf '%s\n' "${porcelain}" >&2
    return 1
  fi
}

# Bring the Host to Deployed using the existing Deploy ladder path (ensure.sh).
# Failed cases leave Host dirty until the next call (ADR-0042).
acceptance_baseline_deployed() {
  local root="${REPO_ROOT:?acceptance_baseline_deployed: REPO_ROOT required}"
  local env_slug="${PLATFORM_ENV:?acceptance_baseline_deployed: PLATFORM_ENV required}"
  acceptance_require_env_tree_at_head || return 1
  "${root}/internals/ensure.sh" --env "${env_slug}"
}
