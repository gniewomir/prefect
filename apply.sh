#!/usr/bin/env bash
# Apply the Stack — bring managed presence to the desired config (ADR-0016).
# Interactive by default (Terraform plan + yes/no). Use --yes for automation.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Closed surface: optional --yes and --env only. Specialist surgery stays raw terraform
# in the Stack dir.
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./apply.sh [--yes] [--env <slug>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"

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

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"
rm -f parked.auto.tfvars # leftover from sticky-parked experiment; no longer used

environment_select_workspace "${STACK_DIR}" "${WORKSPACE}" || fail "could not select Environment workspace '${WORKSPACE}'"

if [[ "${YES}" == true ]]; then
  terraform apply -input=false -auto-approve
else
  terraform apply
fi

echo
echo "Apply complete."
