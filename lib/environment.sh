#!/usr/bin/env bash
# Environment selection for Prefect operator CLI (ADR-0019).
# Sourced by Apply / Park / Teardown (and later runners / Host helpers).
# Safe by default: omitted / default / test → Terraform workspace `default`.
#
# After environment_parse_args: ENVIRONMENT_RAW (slug or empty), ENVIRONMENT_REST (argv array).

# Resolve an Environment slug (or empty) to a Terraform workspace name.
# Prints the workspace on stdout. Fails closed on invalid / ambiguous slugs.
environment_workspace_for() {
  local slug="${1-}"
  case "${slug}" in
    "" | default | test)
      printf '%s\n' "default"
      return 0
      ;;
  esac
  # Open-ended slugs, but reject anything unsafe for a Terraform workspace name
  # or that would silently collide with the default/test alias table.
  if ! printf '%s' "${slug}" | grep -Eq '^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$'; then
    echo "FAIL: invalid --env slug '${slug}' (use lowercase [a-z0-9_-], no leading/trailing hyphen/underscore)" >&2
    return 1
  fi
  printf '%s\n' "${slug}"
}

# Parse argv for a single optional --env / --env=<slug>.
# Sets ENVIRONMENT_RAW and ENVIRONMENT_REST. Fails on missing value or duplicate --env.
environment_parse_args() {
  ENVIRONMENT_RAW=""
  ENVIRONMENT_REST=()
  local seen_env=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        if [[ "${seen_env}" == true ]]; then
          echo "FAIL: duplicate --env (specify Environment once)" >&2
          return 1
        fi
        if [[ $# -lt 2 ]]; then
          echo "FAIL: --env requires a slug (e.g. --env test)" >&2
          return 1
        fi
        ENVIRONMENT_RAW="$2"
        seen_env=true
        shift 2
        ;;
      --env=*)
        if [[ "${seen_env}" == true ]]; then
          echo "FAIL: duplicate --env (specify Environment once)" >&2
          return 1
        fi
        ENVIRONMENT_RAW="${1#--env=}"
        if [[ -z "${ENVIRONMENT_RAW}" ]]; then
          echo "FAIL: --env requires a slug (e.g. --env=test)" >&2
          return 1
        fi
        seen_env=true
        shift
        ;;
      *)
        ENVIRONMENT_REST+=("$1")
        shift
        ;;
    esac
  done
}

# Select (create if missing) the Terraform workspace for this invocation.
# Always selects explicitly — does not trust a leftover current workspace.
environment_select_workspace() {
  local stack_dir="$1"
  local workspace="$2"
  if [[ -z "${stack_dir}" ]]; then
    echo "FAIL: environment_select_workspace: stack_dir required" >&2
    return 1
  fi
  if [[ -z "${workspace}" ]]; then
    echo "FAIL: environment_select_workspace: workspace required" >&2
    return 1
  fi
  if ! command -v terraform >/dev/null; then
    echo "FAIL: terraform not found" >&2
    return 1
  fi
  (
    cd "${stack_dir}"
    if terraform workspace select "${workspace}" >/dev/null 2>&1; then
      exit 0
    fi
    terraform workspace new "${workspace}" >/dev/null
  )
}
