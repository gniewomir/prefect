#!/usr/bin/env bash
# Acceptance Test: Reserved IP assigned and matches Stack output
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
[[ -n "${STATE_JSON:-}" ]] || fail "fixture missing STATE_JSON (run via ./test.sh)"

ASSIGNED="$(echo "${STATE_JSON}" | jq -r '
  .values.root_module.resources[]
  | select(.type == "digitalocean_reserved_ip" and .name == "web")
  | .values.ip_address
')"
[[ "${ASSIGNED}" == "${IP}" ]] || fail "Reserved IP output ${IP} != State ${ASSIGNED}"
pass "Reserved IP assigned and exported"
