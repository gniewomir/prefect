#!/usr/bin/env bash
# Park the Stack — destroy everything in State except the preserve whitelist.
# Durables (Reserved IP + Host Volume + Domain) carry prevent_destroy; that is the
# Durable backstop. Config stays Applied; the next ./apply.sh recreates non-durables.
# Guards protect Durables, not operator Apply (ADR-0016).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Requires: terraform; DIGITALOCEAN_TOKEN; TF_VAR_DIGITALOCEAN_PUBLIC_KEY
# Usage: ./park.sh [--env <slug>]
# Confirm with exact: park
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"

# Keep these; destroy every other address currently in State.
# Durables must also have lifecycle.prevent_destroy — that is the source of truth
# if this list drifts. Cloud Project + Reserved IP floatingip membership stay so
# Durables do not leave Prefect.
# Domain Durables (for_each) are matched in is_preserved by address prefix (ADR-0020).
PRESERVE=(
  digitalocean_reserved_ip.web
  digitalocean_volume.web
  digitalocean_project.prefect
  digitalocean_project_resources.reserved_ip
  terraform_data.durable_destroy_unlock_gate
)

fail() { echo "FAIL: $*" >&2; exit 1; }

is_preserved() {
  local addr="$1"
  local p
  for p in "${PRESERVE[@]}"; do
    [[ "${addr}" == "${p}" ]] && return 0
  done
  # for_each Domain Durable instances (zone + Stack-authored A records)
  case "${addr}" in
    digitalocean_domain.this\[*|digitalocean_record.a\[*) return 0 ;;
  esac
  return 1
}

environment_parse_args "$@" || exit 1
for arg in "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"; do
  fail "unknown argument: ${arg} (only optional --env is accepted)"
done
WORKSPACE="$(environment_workspace_for "${ENVIRONMENT_RAW}")" || exit 1

command -v terraform >/dev/null || fail "terraform not found"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] || fail "DIGITALOCEAN_TOKEN is not set"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY is not set"

cd "${STACK_DIR}"
rm -f parked.auto.tfvars # leftover from sticky-parked experiment; no longer used

environment_select_workspace "${STACK_DIR}" "${WORKSPACE}" || fail "could not select Environment workspace '${WORKSPACE}'"

target_args=()
while IFS= read -r addr; do
  [[ -z "${addr}" ]] && continue
  if is_preserved "${addr}"; then
    continue
  fi
  target_args+=(-target="${addr}")
done < <(terraform state list)

if [[ ${#target_args[@]} -eq 0 ]]; then
  echo
  echo "Already Parked (State has only preserved addresses). Durables still bill if present."
  exit 0
fi

echo "WARNING: Park keeps Durables (Reserved IP, Host Volume, and Domain)."
echo "         They remain in the provider and continue to bill while Parked."
echo "         Teardown (./teardown.sh) is the full wipe when you intend to stop billing."
echo
echo "Park plan (destroy State except preserve whitelist; Durables use prevent_destroy):"
echo
echo "Preserved:"
printf '  %s\n' "${PRESERVE[@]}"
echo "  digitalocean_domain.this[*]  (for_each Domain zones)"
echo "  digitalocean_record.a[*]     (for_each Domain A records)"
echo
echo "Destroy targets:"
for ((i = 0; i < ${#target_args[@]}; i += 1)); do
  # target_args entries are -target=ADDR
  printf '  %s\n' "${target_args[$i]#-target=}"
done
echo

set +e
terraform plan -destroy -detailed-exitcode -input=false "${target_args[@]}"
plan_rc=$?
set -e

case "${plan_rc}" in
  0)
    echo
    echo "Already Parked (destroy plan empty). Durables still bill if present."
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
echo "To Apply again: ./apply.sh"
