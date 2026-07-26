#!/usr/bin/env bash
# Teardown the Stack — full wipe including Durables (Reserved IP + Host Volume + Domain).
# Writes durable_destroy_override.tf and passes -var=allow_durable_destroy=true
# so prevent_destroy lifts; removes the override afterward (ADR-0016).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./teardown.sh [--env <slug>]
# Confirm with exact: teardown
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
OVERRIDE="${STACK_DIR}/durable_destroy_override.tf"
OVERRIDE_EXAMPLE="${STACK_DIR}/durable_destroy_override.tf.example"
UNLOCK_VAR=(-var=allow_durable_destroy=true)
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

remove_override() {
  rm -f "${OVERRIDE}"
}

environment_parse_args "$@" || exit 1
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  fail "unknown argument: ${arg} (only optional --env is accepted)"
done
WORKSPACE="$(environment_workspace_for "${ENVIRONMENT_RAW}")" || exit 1

command -v terraform >/dev/null || fail "terraform not found"
[[ -f "${OVERRIDE_EXAMPLE}" ]] || fail "missing ${OVERRIDE_EXAMPLE}"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"
rm -f parked.auto.tfvars # leftover from sticky-parked experiment; no longer used

environment_select_workspace "${STACK_DIR}" "${WORKSPACE}" || fail "could not select Environment workspace '${WORKSPACE}'"

# Never leave the Durable unlock armed after this script exits.
trap remove_override EXIT

state_addrs=()
while IFS= read -r addr; do
  [[ -z "${addr}" ]] && continue
  state_addrs+=("${addr}")
done < <(terraform state list)

if [[ ${#state_addrs[@]} -eq 0 ]]; then
  echo
  echo "Already empty (State has no addresses). Nothing to Teardown."
  exit 0
fi

cp "${OVERRIDE_EXAMPLE}" "${OVERRIDE}"

echo "WARNING: Teardown permanently removes every Stack-managed resource,"
echo "         including Durables (Reserved IP, Host Volume, and Domain)."
echo "         Billing for those Durables stops only after this wipe."
echo "         Prefer Park (./park.sh) when you intend to Apply again soon."
echo
echo "Teardown plan (full destroy with Durable unlock):"
echo
echo "State addresses:"
printf '  %s\n' "${state_addrs[@]}"
echo

set +e
terraform plan -destroy -detailed-exitcode -input=false "${UNLOCK_VAR[@]}"
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    echo
    echo "Already empty (destroy plan empty)."
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
printf "Type exactly 'teardown' to proceed: "
read -r confirm
[[ "${confirm}" == "teardown" ]] || fail "aborted (expected exact 'teardown')"

terraform destroy -input=false -auto-approve "${UNLOCK_VAR[@]}"

echo
echo "Teardown complete. State should be empty; Durables are gone from the provider."
echo "To Apply again: ./apply.sh"
