#!/usr/bin/env bash
# Host delivery seam (lib/host-delivery.sh) on Host-session. Stubs host_ssh — no cloud.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"
# shellcheck source=host-delivery.sh
source "${REPO_ROOT}/internals/lib/host-delivery.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/host-delivery-test.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

host_session_bind verify "203.0.113.10" || fail "bind should succeed"

SSH_CALLS="${TMP_DIR}/ssh.calls"
FAKE_REMOTE="${TMP_DIR}/fake-remote"
mkdir -p "${FAKE_REMOTE}"
: >"${SSH_CALLS}"

# Stub Host-session transport: first ship call extracts ustar stdin into FAKE_REMOTE/<root>;
# subsequent calls only record the remote command.
host_ssh() {
  local remote_cmd="$*"
  printf '%s\n' "${remote_cmd}" >>"${SSH_CALLS}"
  if [[ "${remote_cmd}" == *"tar -C "* ]]; then
    # Mirror Host extract: wipe then unpack under FAKE_REMOTE + remote root path.
    local root
    root="$(printf '%s\n' "${remote_cmd}" | sed -n 's/.*mkdir -p \([^ ]*\).*/\1/p')"
    [[ -n "${root}" ]] || fail "ship remote cmd missing mkdir -p root; got: ${remote_cmd}"
    local dest="${FAKE_REMOTE}${root}"
    rm -rf "${dest}"
    mkdir -p "${dest}"
    tar -C "${dest}" -xf -
    return 0
  fi
  return 0
}

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/host-delivery-stage.XXXXXX")"
printf 'payload\n' >"${STAGE}/entry.sh"
printf 'lib\n' >"${STAGE}/helper.sh"

host_delivery_run "${STAGE}" "/tmp/platform-purge" \
  "PLATFORM_USER=platform bash /tmp/platform-purge/entry.sh" \
  || fail "host_delivery_run should succeed"

[[ -f "${FAKE_REMOTE}/tmp/platform-purge/entry.sh" ]] \
  || fail "shipped entry.sh missing under fake remote root"
[[ -f "${FAKE_REMOTE}/tmp/platform-purge/helper.sh" ]] \
  || fail "shipped helper.sh missing under fake remote root"
[[ "$(cat "${FAKE_REMOTE}/tmp/platform-purge/entry.sh")" == "payload" ]] \
  || fail "entry.sh payload mismatch"

mapfile_count="$(wc -l <"${SSH_CALLS}" | tr -d ' ')"
[[ "${mapfile_count}" -eq 2 ]] \
  || fail "want 2 host_ssh calls (ship + run), got ${mapfile_count}: $(cat "${SSH_CALLS}")"

ship_line="$(sed -n '1p' "${SSH_CALLS}")"
printf '%s\n' "${ship_line}" | grep -Fq "rm -rf /tmp/platform-purge" \
  || fail "ship must replace remote root; got: ${ship_line}"
printf '%s\n' "${ship_line}" | grep -Fq "mkdir -p /tmp/platform-purge" \
  || fail "ship must mkdir remote root; got: ${ship_line}"
printf '%s\n' "${ship_line}" | grep -Fq "tar -C /tmp/platform-purge -xf -" \
  || fail "ship must extract ustar into remote root; got: ${ship_line}"

run_line="$(sed -n '2p' "${SSH_CALLS}")"
[[ "${run_line}" == "PLATFORM_USER=platform bash /tmp/platform-purge/entry.sh" ]] \
  || fail "run cmd mismatch; got: ${run_line}"
pass "host_delivery_run ships stage to remote root then runs remote cmd"

# Fail closed: missing stage
if host_delivery_run "${TMP_DIR}/no-such-stage" "/tmp/x" "true" >/dev/null 2>&1; then
  fail "host_delivery_run should fail when stage is missing"
fi
pass "host_delivery_run fails closed on missing stage"

# Fail closed: no Host-session
if bash -c "
  source '${REPO_ROOT}/internals/lib/ssh.sh'
  source '${REPO_ROOT}/internals/lib/host-delivery.sh'
  host_delivery_run '${STAGE}' '/tmp/x' 'true'
" >/dev/null 2>&1; then
  fail "host_delivery_run should fail with no Host-session"
fi
pass "host_delivery_run fails closed with no Host-session"
