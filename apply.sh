#!/usr/bin/env bash
# Apply the Stack — converge Durables and request Recreatable presence (ADR-0025).
# Plans first; an empty presence plan means Already Applied (stable condition).
# Interactive by default (plan + Terraform apply confirm). Use --yes for automation.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Closed surface: optional --yes and --env only. Specialist surgery stays raw terraform
# in the Stack dir.
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./apply.sh [--yes] [--env <slug>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
PRESENCE_VAR=(-var=recreatables_present=true)
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=lib/adopt.sh
source "${REPO_ROOT}/lib/adopt.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

environment_parse_args "$@" || exit 1
YES=false
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  case "${arg}" in
    --yes) YES=true ;;
    *) fail "unknown argument: ${arg} (only optional --yes and --env are accepted)" ;;
  esac
done

WORKSPACE="$(environment_workspace_for "${ENVIRONMENT_RAW}")" || exit 1

command -v terraform >/dev/null || fail "terraform not found"

"${REPO_ROOT}/lib/check-cloud-init-ascii.sh"
"${REPO_ROOT}/lib/check-ssh-port-twins.sh"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"

environment_select_workspace "${STACK_DIR}" "${WORKSPACE}" || fail "could not select Environment workspace '${WORKSPACE}'"

adopt_preflight apply "${ENVIRONMENT_RAW}" || exit 1

echo "Apply plan (complete plan with Recreatable presence enabled):"
echo

set +e
terraform plan -detailed-exitcode -input=false "${PRESENCE_VAR[@]}"
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    echo
    echo "Already Applied (presence plan empty)."
    exit 0
    ;;
  1)
    fail "terraform plan failed"
    ;;
  2)
    ;;
  *)
    fail "terraform plan exited with unexpected code ${plan_rc}"
    ;;
esac

if [[ "${YES}" == true ]]; then
  terraform apply -input=false -auto-approve "${PRESENCE_VAR[@]}"
else
  terraform apply "${PRESENCE_VAR[@]}"
fi

echo
echo "Apply complete."
