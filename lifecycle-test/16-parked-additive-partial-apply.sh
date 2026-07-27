#!/usr/bin/env bash
# Lifecycle Test: Parked additive Domain + partial Apply recovery (ADR-0025 / #64).
# Case-owned Park → stage domains.override.json → Apply with invalid public key
# (Recreatable fault after Durable convergence) → restore key → normal Apply →
# empty re-Apply → Teardown with override → remove override → committed re-Apply.
# Recovery-only: does not cover clean Parked-additive happy path (#65).
# Leftover Stack state on success: Applied (committed Domains only; no fixture Durable).
# On failure: may leave Parked, Applied with override, empty after Teardown, or mid-Apply —
# remove config/environments/<slug>/domains.override.json if present, then
# ./apply.sh or ./teardown.sh as needed.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./lifecycle-test.sh)"
[[ -d "${STACK_DIR}" ]] || fail "missing Stack dir ${STACK_DIR}"
[[ -n "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY:-}" ]] \
  || fail "TF_VAR_DIGITALOCEAN_PUBLIC_KEY must be set (real key for recovery Apply)"

trap 'remove_domain_override' EXIT

IP="$(stack_reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (Apply the Stack before this Lifecycle Test)"
export IP

PROJECT_ID_BEFORE="$(stack_cloud_project_id)"
[[ -n "${PROJECT_ID_BEFORE}" ]] || fail "Cloud Project not found at provider before Park"
VOLUME_ID_BEFORE="$(stack_host_volume_id)"
[[ -n "${VOLUME_ID_BEFORE}" ]] || fail "Host Volume not found at provider before Park"
DOMAINS_BEFORE="$(stack_domain_names)"
[[ -n "${DOMAINS_BEFORE}" ]] || fail "committed Domains empty — additive fixture needs a base apex"

assert_host_present
assert_host_membership present
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"
assert_domains_present "${IP}"

echo "Parking Stack before additive partial-Apply scenario (confirming via stdin) ..."
printf 'park\n' | "${REPO_ROOT}/park.sh" --env "${PREFECT_ENV}"

assert_host_absent
assert_host_membership absent
assert_reserved_ip_present "${IP}"
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"
assert_volume_present
assert_domains_present "${IP}"
pass "verified Parked before staging additive Domain fixture"

FIXTURE_APEX="$(write_additive_domain_override)"
[[ -n "${FIXTURE_APEX}" ]] || fail "additive Domain fixture apex empty"
pass "wrote Domain override with fixture ${FIXTURE_APEX} while Parked"

echo "Apply with invalid Recreatable public key (expect Durable converge, then fail) ..."
set +e
fail_out="$(apply_with_public_key "$(lifecycle_invalid_public_key)" 2>&1)"
fail_rc=$?
set -e
[[ "${fail_rc}" -ne 0 ]] || fail "Apply with invalid public key was expected to fail"
echo "${fail_out}" | grep -Eqi 'SSH Key|Fingerprint could not be generated|your key is valid' \
  || {
    echo "${fail_out}" >&2
    fail "failed Apply did not look like Recreatable SSH key rejection"
  }
pass "failed Apply attributed to invalid SSH public key (Recreatable phase)"

AFTER_FAIL_IP="$(stack_reserved_ip)"
[[ "${AFTER_FAIL_IP}" == "${IP}" ]] \
  || fail "Reserved IP changed during failed Apply: before=${IP} after=${AFTER_FAIL_IP}"
PROJECT_ID_AFTER_FAIL="$(stack_cloud_project_id)"
[[ "${PROJECT_ID_AFTER_FAIL}" == "${PROJECT_ID_BEFORE}" ]] \
  || fail "Cloud Project id changed during failed Apply"
VOLUME_ID_AFTER_FAIL="$(stack_host_volume_id)"
[[ "${VOLUME_ID_AFTER_FAIL}" == "${VOLUME_ID_BEFORE}" ]] \
  || fail "Host Volume id changed during failed Apply"

DOMAINS_AFTER_FAIL="$(stack_domain_names)"
echo "${DOMAINS_AFTER_FAIL}" | grep -Fxq "${FIXTURE_APEX}" \
  || fail "fixture Domain ${FIXTURE_APEX} missing from assignment after failed Apply"
while IFS= read -r zone; do
  [[ -z "${zone}" ]] && continue
  echo "${DOMAINS_AFTER_FAIL}" | grep -Fxq "${zone}" \
    || fail "prior Domain ${zone} missing after failed Apply"
done <<< "${DOMAINS_BEFORE}"

assert_host_absent
assert_host_membership absent
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"
assert_domains_present "${IP}"
(cd "${STACK_DIR}" && terraform state list) | grep -Fq "digitalocean_domain.this[\"${FIXTURE_APEX}\"]" \
  || fail "fixture Domain ${FIXTURE_APEX} missing from State after failed Apply"
pass "after failed Apply: Durables (incl. fixture) present in provider+State; Host still absent"

echo "Retry Apply with real public key (normal ./apply.sh; parent TF_VAR unchanged) ..."
"${REPO_ROOT}/apply.sh" --yes --env "${PREFECT_ENV}"

AFTER_IP="$(stack_reserved_ip)"
[[ "${AFTER_IP}" == "${IP}" ]] \
  || fail "Reserved IP changed during recovery Apply: before=${IP} after=${AFTER_IP}"
export IP="${AFTER_IP}"

PROJECT_ID_AFTER="$(stack_cloud_project_id)"
[[ "${PROJECT_ID_AFTER}" == "${PROJECT_ID_BEFORE}" ]] \
  || fail "Cloud Project id changed during recovery Apply"
VOLUME_ID_AFTER="$(stack_host_volume_id)"
[[ "${VOLUME_ID_AFTER}" == "${VOLUME_ID_BEFORE}" ]] \
  || fail "Host Volume id changed during recovery Apply"

DOMAINS_AFTER="$(stack_domain_names)"
echo "${DOMAINS_AFTER}" | grep -Fxq "${FIXTURE_APEX}" \
  || fail "fixture Domain ${FIXTURE_APEX} missing after recovery Apply"
while IFS= read -r zone; do
  [[ -z "${zone}" ]] && continue
  echo "${DOMAINS_AFTER}" | grep -Fxq "${zone}" \
    || fail "prior Domain ${zone} missing after recovery Apply"
done <<< "${DOMAINS_BEFORE}"

assert_host_present
assert_host_membership present
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"
assert_domains_present "${IP}"
pass "recovery Apply restored Recreatables and preserved Durables"

echo "Repeating Apply after recovery (expect empty plan) ..."
assert_apply_noop

echo "Tearing down Stack with override still present (confirming via stdin) ..."
printf 'teardown\n' | "${REPO_ROOT}/teardown.sh" --env "${PREFECT_ENV}"

assert_stack_empty
assert_domains_absent "$(printf '%s\n%s\n' "${DOMAINS_BEFORE}" "${FIXTURE_APEX}")"

remove_domain_override
trap - EXIT

echo "Re-Applying committed Domains only ..."
"${REPO_ROOT}/apply.sh" --yes --env "${PREFECT_ENV}"

RESTORE_IP="$(stack_reserved_ip)"
[[ -n "${RESTORE_IP}" ]] || fail "no reserved_ip after committed re-Apply"
export IP="${RESTORE_IP}"

DOMAINS_RESTORED="$(stack_domain_names)"
echo "${DOMAINS_RESTORED}" | grep -Fxq "${FIXTURE_APEX}" \
  && fail "fixture Domain ${FIXTURE_APEX} still in assignment after committed re-Apply"
while IFS= read -r zone; do
  [[ -z "${zone}" ]] && continue
  echo "${DOMAINS_RESTORED}" | grep -Fxq "${zone}" \
    || fail "committed Domain ${zone} missing after re-Apply"
done <<< "${DOMAINS_BEFORE}"
assert_domains_present "${IP}"
assert_domains_absent "${FIXTURE_APEX}"

assert_host_present
assert_host_membership present
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"

echo "Repeating Apply after committed restore (expect empty plan) ..."
assert_apply_noop

pass "Parked additive Apply recovers after partial Recreatable failure"
