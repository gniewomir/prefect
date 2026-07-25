#!/usr/bin/env bash
# Acceptance Test: Cloud Project Prefect owns the Host and Host Volume
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${STATE_JSON:-}" ]] || fail "fixture missing STATE_JSON (run via ./test.sh)"
[[ -n "${HOST_JSON:-}" && "${HOST_JSON}" != "null" ]] || fail "fixture missing HOST_JSON (run via ./test.sh)"

PROJECT_JSON="$(echo "${STATE_JSON}" | jq -c '
  .values.root_module.resources[]
  | select(.type == "digitalocean_project" and .name == "prefect")
  | .values
')"
[[ -n "${PROJECT_JSON}" && "${PROJECT_JSON}" != "null" ]] || fail "Cloud Project digitalocean_project.prefect not in State"
echo "${PROJECT_JSON}" | jq -e '.name == "prefect-test"' >/dev/null || fail "Cloud Project name != prefect-test"
echo "${PROJECT_JSON}" | jq -e '.environment == "Production"' >/dev/null || fail "Cloud Project environment != Production"
echo "${PROJECT_JSON}" | jq -e '.is_default == false' >/dev/null || fail "Cloud Project must not be account default"

# Host membership is a separate project_resources so Park can destroy the Host without
# pulling Cloud Project (and Durables) into the destroy graph (ADR-0016 / park design).
HOST_ASSIGN_JSON="$(echo "${STATE_JSON}" | jq -c '
  .values.root_module.resources[]
  | select(.type == "digitalocean_project_resources" and .name == "web_host")
  | .values
')"
[[ -n "${HOST_ASSIGN_JSON}" && "${HOST_ASSIGN_JSON}" != "null" ]] \
  || fail "Host Cloud Project assignment digitalocean_project_resources.web_host not in State"
HOST_URN="$(echo "${HOST_JSON}" | jq -r '.urn')"
echo "${HOST_ASSIGN_JSON}" | jq -e --arg urn "${HOST_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Host URN not assigned to Cloud Project Prefect via web_host"

VOLUME_URN="$(echo "${STATE_JSON}" | jq -r '
  .values.root_module.resources[]
  | select(.type == "digitalocean_volume" and .name == "web")
  | .values.urn
')"
[[ -n "${VOLUME_URN}" && "${VOLUME_URN}" != "null" ]] || fail "Host Volume URN not in State"
echo "${PROJECT_JSON}" | jq -e --arg urn "${VOLUME_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Host Volume URN not assigned to Cloud Project Prefect"

pass "Cloud Project Prefect owns Host and Host Volume"
