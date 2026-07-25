#!/usr/bin/env bash
# Park the Stack — destroy non-durables; keep Durables (Reserved IP + Host Volume)
# in State for a later Apply (ADR-0016). Config stays Applied; the next ordinary
# terraform apply recreates the Host. Guards protect Durables, not operator Apply.
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./park.sh
# Confirm with exact: park
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"

# Non-durables only. Never target Durables or Cloud Project Prefect.
PARK_TARGETS=(
  digitalocean_reserved_ip_assignment.web
  digitalocean_project_resources.web_host
  digitalocean_firewall.public_web
  digitalocean_droplet.web
  digitalocean_ssh_key.web
  digitalocean_tag.office
  digitalocean_tag.public_web
)

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v terraform >/dev/null || fail "terraform not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"
rm -f parked.auto.tfvars # leftover from sticky-parked experiment; no longer used

target_args=()
for addr in "${PARK_TARGETS[@]}"; do
  target_args+=(-target="${addr}")
done

echo "WARNING: Park keeps Durables (Reserved IP and Host Volume)."
echo "         They remain in the provider and continue to bill while Parked."
echo "         Teardown (./teardown.sh) is the full wipe when you intend to stop billing."
echo
echo "Park plan (destroy non-durables only; Durables + Cloud Project kept):"
echo

set +e
terraform plan -destroy -detailed-exitcode -input=false "${target_args[@]}"
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    echo
    echo "Already Parked (no targeted non-durables in State). Durables still bill if present."
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
printf "Type exactly 'park' to proceed: "
read -r confirm
[[ "${confirm}" == "park" ]] || fail "aborted (expected exact 'park')"

terraform destroy -input=false -auto-approve "${target_args[@]}"

echo
echo "Park complete. Durables remain in State/provider and still bill."
echo "To Apply again: (cd ${STACK_DIR} && terraform apply)"
