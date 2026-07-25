#!/usr/bin/env bash
# Park the Stack — remove the Host and other non-durables; keep Durables
# (Reserved IP + Host Volume) Stack-managed for a later Apply (ADR-0016).
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./park.sh
# Confirm with exact: park
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
PARKED_TFVARS="${STACK_DIR}/parked.auto.tfvars"

fail() { echo "FAIL: $*" >&2; exit 1; }

persist_parked_marker() {
  printf '%s\n' 'parked = true' > "${PARKED_TFVARS}"
}

command -v terraform >/dev/null || fail "terraform not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"

echo "WARNING: Park keeps Durables (Reserved IP and Host Volume)."
echo "         They remain in the provider and continue to bill while Parked."
echo "         Teardown (./teardown.sh) is the full wipe when you intend to stop billing."
echo
echo "Park plan (non-durables removed; Durables + Cloud Project kept):"
echo

# Preview with -var so an aborted confirm does not leave parked.auto.tfvars behind.
set +e
terraform plan -detailed-exitcode -input=false -var=parked=true
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    # Persist marker if missing so later bare plans stay Parked.
    persist_parked_marker
    echo
    echo "Already Parked (or no non-durable changes). Durables still bill if present."
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

echo
printf "Type exactly 'park' to proceed: "
read -r confirm
[[ "${confirm}" == "park" ]] || fail "aborted (expected exact 'park')"

persist_parked_marker
terraform apply -input=false -auto-approve

echo
echo "Park complete. Durables remain in State/provider and still bill."
echo "To Apply again: rm -f ${PARKED_TFVARS} && (cd ${STACK_DIR} && terraform apply)"
