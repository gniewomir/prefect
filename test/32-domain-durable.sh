#!/usr/bin/env bash
# Acceptance Test: Domain Durables in Applied State (ADR-0020)
# Empty domains config → no Domain resources. When Domains are configured, every
# Stack-authored A record points at the Reserved IP and Domain URNs sit on the
# Environment Cloud Project. Does not Park or Teardown.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
[[ -n "${STATE_JSON:-}" ]] || fail "fixture missing STATE_JSON (run via ./test.sh)"

DURABLE_ASSIGN_JSON="$(echo "${STATE_JSON}" | jq -c '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_project_resources" and .name == "durables")
  | .values
')"
[[ -n "${DURABLE_ASSIGN_JSON}" && "${DURABLE_ASSIGN_JSON}" != "null" ]] \
  || fail "Durable Cloud Project memberships not in State"

DOMAIN_COUNT="$(echo "${STATE_JSON}" | jq '
  [def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_domain" and .name == "this")] | length
')"

RECORD_COUNT="$(echo "${STATE_JSON}" | jq '
  [def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_record" and .name == "a")] | length
')"

if [[ "${DOMAIN_COUNT}" -eq 0 ]]; then
  [[ "${RECORD_COUNT}" -eq 0 ]] || fail "Domain A records present without Domain zones"
  pass "Domain Durables absent (0 Domains configured)"
  exit 0
fi

# Every Domain URN is on the Cloud Project Durable set.
while IFS= read -r urn; do
  [[ -n "${urn}" && "${urn}" != "null" ]] || fail "Domain missing urn in State"
  echo "${DURABLE_ASSIGN_JSON}" | jq -e --arg urn "${urn}" '.resources | index($urn) != null' >/dev/null \
    || fail "Domain URN ${urn} not assigned to Cloud Project Prefect"
done < <(echo "${STATE_JSON}" | jq -r '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_domain" and .name == "this")
  | .values.urn
')

# Every Stack-authored A record points at the Environment Reserved IP.
while IFS= read -r row; do
  [[ -n "${row}" ]] || continue
  rtype="$(echo "${row}" | jq -r '.type')"
  value="$(echo "${row}" | jq -r '.value')"
  [[ "${rtype}" == "A" ]] || fail "Domain record type ${rtype} != A"
  [[ "${value}" == "${IP}" ]] || fail "Domain A value ${value} != Reserved IP ${IP}"
done < <(echo "${STATE_JSON}" | jq -c '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_record" and .name == "a")
  | .values
')

[[ "${RECORD_COUNT}" -ge "${DOMAIN_COUNT}" ]] \
  || fail "fewer Domain A records (${RECORD_COUNT}) than Domains (${DOMAIN_COUNT})"

pass "Domain Durables on Cloud Project; A records → Reserved IP"
