#!/usr/bin/env bash
# Acceptance Test: Cloud Project Prefect owns the Host
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
echo "${PROJECT_JSON}" | jq -e '.name == "Prefect"' >/dev/null || fail "Cloud Project name != Prefect"
echo "${PROJECT_JSON}" | jq -e '.environment == "Production"' >/dev/null || fail "Cloud Project environment != Production"
echo "${PROJECT_JSON}" | jq -e '.is_default == false' >/dev/null || fail "Cloud Project must not be account default"
HOST_URN="$(echo "${HOST_JSON}" | jq -r '.urn')"
echo "${PROJECT_JSON}" | jq -e --arg urn "${HOST_URN}" '.resources | index($urn) != null' >/dev/null \
  || fail "Host URN not assigned to Cloud Project Prefect"
pass "Cloud Project Prefect owns Host"
