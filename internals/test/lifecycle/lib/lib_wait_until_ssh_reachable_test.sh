#!/usr/bin/env bash
# Seam: wait_until_ssh_reachable — forgets stale known_hosts before polling SSH.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
export REPO_ROOT="${REAL_ROOT}"
# shellcheck source=lib.sh
source "${CASE_DIR}/lib.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wait-ssh.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
TIMELINE="${TMP}/timeline.record"

propraetor_ssh_forget_host() {
  printf 'forget:%s\n' "$1" >>"${TIMELINE}"
}
acceptance_host_session() {
  printf 'bind\n' >>"${TIMELINE}"
}
host_ssh() {
  printf 'ssh:%s\n' "$*" >>"${TIMELINE}"
  return 0
}

export IP="203.0.113.40"
: >"${TIMELINE}"
wait_until_ssh_reachable
got="$(cat "${TIMELINE}")"
expected="$(printf '%s\n' 'forget:203.0.113.40' 'bind' 'ssh:true')"
[[ "${got}" == "${expected}" ]] \
  || fail "expected forget→bind→ssh; got:"$'\n'"${got}"
pass "wait_until_ssh_reachable forgets known_hosts before SSH probe"

echo "All wait_until_ssh_reachable checks passed."
