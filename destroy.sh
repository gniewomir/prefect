#!/usr/bin/env bash
# Destroy the Stack — development helper to remove everything State manages so you
# can re-apply quickly between iterations. Not a production runbook.
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
#   (Terraform still validates the input variable even though Destroy does not use it).
# Usage: ./destroy.sh
# Confirm with exact: yes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v terraform >/dev/null || fail "terraform not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"

echo "Destroy plan (what will be removed):"
echo

set +e
terraform plan -destroy -detailed-exitcode
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    echo
    echo "Nothing to Destroy (State manages no resources, or destroy plan is empty)."
    exit 0
    ;;
  1)
    fail "terraform plan -destroy failed"
    ;;
  2)
    ;;
  *)
    fail "terraform plan -destroy exited with unexpected code ${plan_rc}"
    ;;
esac

echo
echo "This will Destroy every resource the Stack currently manages."
printf "Type exactly 'yes' to proceed: "
read -r confirm
[[ "${confirm}" == "yes" ]] || fail "aborted (expected exact 'yes')"

terraform destroy -auto-approve

echo "Destroy complete."
