#!/usr/bin/env bash
# Acceptance Test: Host Volume size and attachment to the Host (ADR-0009)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${STATE_JSON:-}" ]] || fail "fixture missing STATE_JSON (run via ./test.sh)"
[[ -n "${HOST_JSON:-}" && "${HOST_JSON}" != "null" ]] || fail "fixture missing HOST_JSON (run via ./test.sh)"

VOLUME_JSON="$(echo "${STATE_JSON}" | jq -c '
  def resources: (.resources[]?), (.child_modules[]? | resources);
  .values.root_module | resources
  | select(.type == "digitalocean_volume" and .name == "web")
  | .values
')"
[[ -n "${VOLUME_JSON}" && "${VOLUME_JSON}" != "null" ]] || fail "Host Volume not in State"

echo "${VOLUME_JSON}" | jq -e '.size == 1' >/dev/null || fail "Host Volume size != 1 GiB"
echo "${VOLUME_JSON}" | jq -e '.region == "fra1"' >/dev/null || fail "Host Volume region != fra1"

VOLUME_ID="$(echo "${VOLUME_JSON}" | jq -r '.id')"
[[ -n "${VOLUME_ID}" && "${VOLUME_ID}" != "null" ]] || fail "Host Volume id missing"

echo "${HOST_JSON}" | jq -e --arg id "${VOLUME_ID}" '.volume_ids | index($id) != null' >/dev/null \
  || fail "Host Volume not attached to Host at create (volume_ids)"

pass "Host Volume 1 GiB attached to Host"
