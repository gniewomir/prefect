#!/usr/bin/env bash
# Acceptance Test: Host metadata (name, region, size, image, Prefect Tag, Role Tag)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[[ -n "${HOST_JSON:-}" && "${HOST_JSON}" != "null" ]] || fail "fixture missing HOST_JSON (run via ./test.sh)"

echo "${HOST_JSON}" | jq -e '.name == "prefect-test-web"' >/dev/null || fail "Host name != prefect-test-web"
echo "${HOST_JSON}" | jq -e '.region == "fra1"' >/dev/null || fail "Host region != fra1"
echo "${HOST_JSON}" | jq -e '.size == "s-1vcpu-512mb-10gb"' >/dev/null || fail "Host size mismatch"
echo "${HOST_JSON}" | jq -e '.image == "ubuntu-26-04-x64"' >/dev/null || fail "Host image mismatch"
echo "${HOST_JSON}" | jq -e '.tags | index("prefect-test") != null' >/dev/null || fail "Host missing Prefect Tag prefect-test"
echo "${HOST_JSON}" | jq -e '.tags | index("prefect-test-public-web") != null' >/dev/null || fail "Host missing Role Tag prefect-test-public-web"
pass "Host metadata (name, region, size, image, Prefect Tag, Role Tag)"
