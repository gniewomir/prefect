#!/usr/bin/env bash
# Lifecycle Test: subtractive Durable config fails closed (ADR-0025 / #63).
# Stages a narrower domains.override.json (drops lex-first committed apex), expects
# normal Apply to fail with Terraform prevent_destroy, asserts Durables unchanged,
# removes the override, and re-Applies committed Domains.
# Leftover Stack state on success: Applied (committed Domains; empty repeated Apply).
# On failure: may leave Applied with override — remove
# config/environments/<slug>/domains.override.json if present, then ./apply.sh.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./lifecycle-test.sh)"
[[ -d "${STACK_DIR}" ]] || fail "missing Stack dir ${STACK_DIR}"

trap 'remove_domain_override' EXIT

IP="$(stack_reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (Apply the Stack before this Lifecycle Test)"
export IP

PROJECT_ID_BEFORE="$(stack_cloud_project_id)"
[[ -n "${PROJECT_ID_BEFORE}" ]] || fail "Cloud Project not found at provider before subtractive Apply"
VOLUME_ID_BEFORE="$(stack_host_volume_id)"
[[ -n "${VOLUME_ID_BEFORE}" ]] || fail "Host Volume not found at provider before subtractive Apply"
DOMAINS_BEFORE="$(stack_domain_names)"
[[ -n "${DOMAINS_BEFORE}" ]] || fail "committed Domains empty — subtractive fixture needs an apex to drop"

assert_host_present
assert_host_membership present
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"
assert_domains_present "${IP}"

HOST_ID_BEFORE="$(provider_host_by_name_json | jq -r '.id | tostring')"
[[ -n "${HOST_ID_BEFORE}" && "${HOST_ID_BEFORE}" != "null" ]] \
  || fail "Host id missing before subtractive Apply"

DROPPED_APEX="$(write_subtractive_domain_override)"
[[ -n "${DROPPED_APEX}" ]] || fail "subtractive Domain fixture apex empty"
echo "${DOMAINS_BEFORE}" | grep -Fxq "${DROPPED_APEX}" \
  || fail "dropped apex ${DROPPED_APEX} was not in committed assignment"
pass "wrote Domain override dropping ${DROPPED_APEX}"

echo "Applying subtractive Domain override (expect prevent_destroy failure) ..."
fail_out="$("${REPO_ROOT}/apply.sh" --yes --env "${PREFECT_ENV}" 2>&1)" && {
  echo "${fail_out}" >&2
  fail "Apply must fail closed on subtractive Durable Domain retirement"
}
echo "${fail_out}" | grep -qi 'prevent_destroy' \
  || fail "subtractive failure must mention prevent_destroy (output: ${fail_out})"
pass "Apply failed closed with prevent_destroy for dropped apex ${DROPPED_APEX}"

AFTER_IP="$(stack_reserved_ip)"
[[ "${AFTER_IP}" == "${IP}" ]] || fail "Reserved IP changed during failed subtractive Apply: before=${IP} after=${AFTER_IP}"
PROJECT_ID_AFTER="$(stack_cloud_project_id)"
[[ "${PROJECT_ID_AFTER}" == "${PROJECT_ID_BEFORE}" ]] \
  || fail "Cloud Project id changed during failed subtractive Apply"
VOLUME_ID_AFTER="$(stack_host_volume_id)"
[[ "${VOLUME_ID_AFTER}" == "${VOLUME_ID_BEFORE}" ]] \
  || fail "Host Volume id changed during failed subtractive Apply"
HOST_ID_AFTER="$(provider_host_by_name_json | jq -r '.id | tostring')"
[[ "${HOST_ID_AFTER}" == "${HOST_ID_BEFORE}" ]] \
  || fail "Host id changed during failed subtractive Apply"
pass "Durable and Host identities unchanged after failed subtractive Apply"

# Override empties configured Domains; assert provider still has prior zones via DOMAINS_BEFORE.
while IFS= read -r zone; do
  [[ -z "${zone}" ]] && continue
  do_api_get "/v2/domains/${zone}" >/dev/null \
    || fail "Domain ${zone} missing at provider after failed subtractive Apply"
  body="$(do_api_get "/v2/domains/${zone}/records")" \
    || fail "Domain ${zone} records list failed after failed subtractive Apply"
  echo "${body}" | jq -e --arg ip "${IP}" \
    '[.domain_records[] | select(.type == "A" and .data == $ip)] | length >= 1' >/dev/null \
    || fail "Domain ${zone} lost A → Reserved IP after failed subtractive Apply"
done <<< "${DOMAINS_BEFORE}"
pass "prior Domains still present at provider (including dropped apex ${DROPPED_APEX})"

assert_host_present
assert_host_membership present
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"

remove_domain_override
trap - EXIT

echo "Re-Applying committed Domains after removing subtractive override ..."
"${REPO_ROOT}/apply.sh" --yes --env "${PREFECT_ENV}"

RESTORE_IP="$(stack_reserved_ip)"
[[ "${RESTORE_IP}" == "${IP}" ]] || fail "Reserved IP changed during committed restore Apply"
DOMAINS_RESTORED="$(stack_domain_names)"
while IFS= read -r zone; do
  [[ -z "${zone}" ]] && continue
  echo "${DOMAINS_RESTORED}" | grep -Fxq "${zone}" \
    || fail "committed Domain ${zone} missing after restore Apply"
done <<< "${DOMAINS_BEFORE}"
assert_domains_present "${IP}"
assert_host_present
assert_host_membership present
assert_reserved_ip_membership "${IP}"
assert_durables_in_cloud_project "${IP}"

echo "Repeating Apply after subtractive cleanup (expect empty plan) ..."
assert_apply_noop

pass "subtractive Durable Domain retirement fails closed"
