#!/usr/bin/env bash
# Acceptance Test: Cloud Project Prefect owns the Host, Host Volume, and Reserved IP
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${STATE_JSON:-}" ]] || fail "fixture missing STATE_JSON (run via ./test.sh)"
[[ -n "${HOST_JSON:-}" && "${HOST_JSON}" != "null" ]] || fail "fixture missing HOST_JSON (run via ./test.sh)"

PROJECT_JSON="$(echo "${STATE_JSON}" | jq -c '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_project" and .name == "prefect")
  | .values
')"
[[ -n "${PROJECT_JSON}" && "${PROJECT_JSON}" != "null" ]] || fail "Cloud Project not in State"
echo "${PROJECT_JSON}" | jq -e '.name == "prefect-test"' >/dev/null || fail "Cloud Project name != prefect-test"
echo "${PROJECT_JSON}" | jq -e '.environment == "Production"' >/dev/null || fail "Cloud Project environment != Production"
echo "${PROJECT_JSON}" | jq -e '.is_default == false' >/dev/null || fail "Cloud Project must not be account default"

# Host membership is owned by the Recreatable module.
HOST_ASSIGN_JSON="$(echo "${STATE_JSON}" | jq -c '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_project_resources" and .name == "web_host")
  | .values
')"
[[ -n "${HOST_ASSIGN_JSON}" && "${HOST_ASSIGN_JSON}" != "null" ]] \
  || fail "Host Cloud Project membership not in State"
HOST_URN="$(echo "${HOST_JSON}" | jq -r '.urn')"
echo "${HOST_ASSIGN_JSON}" | jq -e --arg urn "${HOST_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Host URN not assigned to Cloud Project Prefect via web_host"

VOLUME_URN="$(echo "${STATE_JSON}" | jq -r '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_volume" and .name == "web")
  | .values.urn
')"
[[ -n "${VOLUME_URN}" && "${VOLUME_URN}" != "null" ]] || fail "Host Volume URN not in State"

# Durable memberships are disjoint from the Host membership and survive Park.
RESERVED_IP="$(echo "${STATE_JSON}" | jq -r '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_reserved_ip" and .name == "web")
  | .values.ip_address
')"
[[ -n "${RESERVED_IP}" && "${RESERVED_IP}" != "null" ]] || fail "Reserved IP not in State"
FLOATING_URN="do:floatingip:${RESERVED_IP}"
DURABLE_ASSIGN_JSON="$(echo "${STATE_JSON}" | jq -c '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_project_resources" and .name == "durables")
  | .values
')"
[[ -n "${DURABLE_ASSIGN_JSON}" && "${DURABLE_ASSIGN_JSON}" != "null" ]] \
  || fail "Durable Cloud Project memberships not in State"
echo "${DURABLE_ASSIGN_JSON}" | jq -e --arg urn "${VOLUME_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Host Volume URN not assigned through Durable memberships"
echo "${DURABLE_ASSIGN_JSON}" | jq -e --arg urn "${FLOATING_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Reserved IP floatingip URN not assigned through Durable memberships"

pass "Cloud Project Prefect owns Host, Host Volume, and Reserved IP"
