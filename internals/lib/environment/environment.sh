#!/usr/bin/env bash
# Environment selection for Propraetor operator CLI (ADR-0019 / ADR-0039).
# Sourced by Apply / Park / Teardown / runners / Host helpers.
# Safe by default: omitted / default / test → Terraform workspace `default`.
# Argv parsing lives in cli.sh; this Module maps slug → workspace / PLATFORM_ENV.
#
# After environment_activate: ENVIRONMENT_RAW (slug or empty), PLATFORM_ENV (cloud slug).

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

# Cloud name slug for an Environment flag value (workspace `default` → `test`).
environment_slug_for() {
  local slug="${1-}"
  case "${slug}" in
    "" | default | test)
      printf '%s\n' "test"
      return 0
      ;;
  esac
  environment_workspace_for "${slug}" >/dev/null || return 1
  printf '%s\n' "${slug}"
}

# Host Volume provider name for an Environment flag value (matches terraform/naming.tf).
environment_volume_name_for() {
  local cloud_slug
  cloud_slug="$(environment_slug_for "${1-}")" || return 1
  printf 'propraetor-%s-web-data\n' "${cloud_slug}"
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
    cd "${stack_dir}" || exit 1
    if terraform workspace select "${workspace}" >/dev/null 2>&1; then
      exit 0
    fi
    terraform workspace new "${workspace}" >/dev/null
  )
}

# Select workspace and set PLATFORM_ENV for nested operator calls.
# Callers pass stack_dir and the raw --env slug (may be empty).
environment_activate() {
  local stack_dir="$1"
  local slug="${2-}"
  # shellcheck disable=SC2034  # ENVIRONMENT_RAW is read by callers after activate
  ENVIRONMENT_RAW="${slug}"
  local workspace
  workspace="$(environment_workspace_for "${slug}")" || return 1
  environment_select_workspace "${stack_dir}" "${workspace}" || return 1
  # Canonical CLI slug for propagation (empty / default → test).
  PLATFORM_ENV="$(environment_slug_for "${slug}")" || return 1
  export PLATFORM_ENV
}
