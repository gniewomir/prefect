#!/usr/bin/env bash
# Park the Stack — request Recreatable absence through a complete Terraform plan.
# Durables remain configured and protected; the next Apply requests presence again.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./park.sh [--env <slug>]
# Confirm with exact: park
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
# shellcheck source=internals/lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"
# shellcheck source=internals/lib/adopt.sh
source "${REPO_ROOT}/internals/lib/adopt.sh"

ABSENCE_VAR=(-var=recreatables_present=false)

fail() { echo "FAIL: $*" >&2; exit 1; }

environment_parse_args "$@" || exit 1
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  fail "unknown argument: ${arg} (only optional --env is accepted)"
done
WORKSPACE="$(environment_workspace_for "${ENVIRONMENT_RAW}")" || exit 1

command -v terraform >/dev/null || fail "terraform not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"

environment_select_workspace "${STACK_DIR}" "${WORKSPACE}" || fail "could not select Environment workspace '${WORKSPACE}'"

adopt_preflight park "${ENVIRONMENT_RAW}" || exit 1

echo "WARNING: Park keeps Durables (Cloud Project, Reserved IP, Host Volume, and Domain)."
echo "         They remain in the provider and continue to bill while Parked."
echo "         Teardown (./teardown.sh) is the full wipe when you intend to stop billing."
echo
echo "Park plan (complete plan with Recreatable presence disabled):"
echo

set +e
terraform plan -detailed-exitcode -input=false "${ABSENCE_VAR[@]}"
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    echo
    echo "Already Parked (destroy plan empty). Durables still bill if present."
    exit 0
    ;;
  1)
    fail "terraform plan failed"
    ;;
  2)
    ;;
  *)
    fail "terraform plan -destroy exited with unexpected code ${plan_rc}"
    ;;
esac

echo
printf "Type exactly 'park' to proceed: "
read -r confirm
[[ "${confirm}" == "park" ]] || fail "aborted (expected exact 'park')"

terraform apply -input=false -auto-approve "${ABSENCE_VAR[@]}"

echo
echo "Park complete. Durables remain in State/provider and still bill."
echo "To Apply again: ./apply.sh"
