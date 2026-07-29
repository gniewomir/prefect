#!/usr/bin/env bash
# Unit tests: recreatables Firewall SSH inbound (ADR-0030). IHP user_data lives in
# ihp-user-data-render_test.sh — this file only covers the Stack Firewall resource.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
TF_MAIN="${REPO_ROOT}/internals/terraform/modules/recreatables/main.tf"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${TF_MAIN}" ]] || fail "missing ${TF_MAIN}"

grep -q 'port_range.*=.*"22"' "${TF_MAIN}" \
  && fail "Firewall must not dual-allow classic :22 after proven cutover"
pass "Firewall does not allow classic :22"

# Only the Prefect twin port should appear as SSH inbound (not a bare "22" rule).
grep -q 'tostring(local.ssh_port)' "${TF_MAIN}" \
  || fail "Firewall SSH inbound must use tostring(local.ssh_port)"
pass "Firewall SSH inbound uses ssh_port twin"
