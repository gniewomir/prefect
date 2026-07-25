#!/usr/bin/env bash
# Apply the Stack — bring managed presence to the desired config (ADR-0016).
# Interactive by default (Terraform plan + yes/no). Use --yes for automation.
# Closed surface: no other flags or Terraform args. Specialist surgery stays
# raw terraform in the Stack dir.
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./apply.sh [--yes]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"

fail() { echo "FAIL: $*" >&2; exit 1; }

YES=false
for arg in "$@"; do
  case "${arg}" in
    --yes) YES=true ;;
    *) fail "unknown argument: ${arg} (only optional --yes is accepted)" ;;
  esac
done

command -v terraform >/dev/null || fail "terraform not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"
rm -f parked.auto.tfvars # leftover from sticky-parked experiment; no longer used

if [[ "${YES}" == true ]]; then
  terraform apply -input=false -auto-approve
else
  terraform apply
fi

echo
echo "Apply complete."
