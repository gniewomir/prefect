#!/usr/bin/env bash
# Unit tests: IHP Done Host Volume mount wait (ADR-0031) + cutover reboot (ADR-0030).
# Stubs cloud-init / sysctl / id / findmnt via PATH — no SSH.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/internals/host-scripts/wait-until-ihp-done.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${SCRIPT}" ]] || fail "missing ${SCRIPT}"

STUBS="$(mktemp -d "${TMPDIR:-/tmp}/ihp-done.XXXXXX")"
trap 'rm -rf "${STUBS}"' EXIT
STATE="${STUBS}/state"
mkdir -p "${STATE}"

cat >"${STUBS}/cloud-init" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "status" && "${2:-}" == "--wait" ]]; then
  echo "status: done"
  exit 0
fi
exit 0
EOF
chmod +x "${STUBS}/cloud-init"

cat >"${STUBS}/sysctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--system" ]]; then
  exit 0
fi
if [[ "${1:-}" == "-n" && "${2:-}" == "net.ipv4.ip_unprivileged_port_start" ]]; then
  echo 80
  exit 0
fi
exit 0
EOF
chmod +x "${STUBS}/sysctl"

cat >"${STUBS}/id" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${STUBS}/id"

cat >"${STUBS}/findmnt" <<'EOF'
#!/usr/bin/env bash
# Succeed after FINDMT_SUCCEED_AFTER attempts (default: never).
set -euo pipefail
if [[ "${1:-}" != "--mountpoint" ]]; then
  exit 1
fi
count_file="${STUB_STATE}/findmnt_count"
n=0
if [[ -f "${count_file}" ]]; then
  n="$(cat "${count_file}")"
fi
n=$((n + 1))
printf '%s\n' "${n}" >"${count_file}"
need="${FINDMT_SUCCEED_AFTER:-999999}"
if [[ "${n}" -ge "${need}" ]]; then
  exit 0
fi
exit 1
EOF
chmod +x "${STUBS}/findmnt"

run_gate() {
  rm -f "${STATE}/findmnt_count"
  env PATH="${STUBS}:/usr/bin:/bin" \
    STUB_STATE="${STATE}" \
    PLATFORM_USER=platform \
    HOST_VOLUME_MOUNT_WAIT_SECONDS="${HOST_VOLUME_MOUNT_WAIT_SECONDS:-30}" \
    HOST_VOLUME_MOUNT_POLL_SECONDS="${HOST_VOLUME_MOUNT_POLL_SECONDS:-1}" \
    FINDMT_SUCCEED_AFTER="${FINDMT_SUCCEED_AFTER:-}" \
    IHP_POWER_STATE_SEM_EPOCH="${IHP_POWER_STATE_SEM_EPOCH:-100}" \
    IHP_BOOT_EPOCH="${IHP_BOOT_EPOCH:-200}" \
    IHP_CUTOVER_REBOOT_WAIT_SECONDS="${IHP_CUTOVER_REBOOT_WAIT_SECONDS:-30}" \
    IHP_CUTOVER_REBOOT_POLL_SECONDS="${IHP_CUTOVER_REBOOT_POLL_SECONDS:-1}" \
    bash "${SCRIPT}" 2>"${STUBS}/err"
}

# --- retries until findmnt succeeds ---
export FINDMT_SUCCEED_AFTER=3
export HOST_VOLUME_MOUNT_WAIT_SECONDS=10
export HOST_VOLUME_MOUNT_POLL_SECONDS=1
run_gate || fail "gate should pass once findmnt succeeds on retry"
count="$(cat "${STATE}/findmnt_count")"
[[ "${count}" -ge 3 ]] || fail "expected at least 3 findmnt attempts, got ${count}"
pass "retries findmnt until Host Volume mount appears"

# --- timeout: message points at host-volume.service ---
export FINDMT_SUCCEED_AFTER=999999
export HOST_VOLUME_MOUNT_WAIT_SECONDS=2
export HOST_VOLUME_MOUNT_POLL_SECONDS=1
if run_gate; then
  fail "gate should fail when mount never appears"
fi
grep -q 'Host Volume mount /var/lib/host-volume missing' "${STUBS}/err" \
  || fail "expected mount-missing message, got: $(cat "${STUBS}/err")"
grep -q 'host-volume.service' "${STUBS}/err" \
  || fail "expected pointer to host-volume.service, got: $(cat "${STUBS}/err")"
pass "on timeout points at host-volume.service"

# --- ADR-0030: cutover reboot required (boot newer than power_state sem) ---
export FINDMT_SUCCEED_AFTER=1
export HOST_VOLUME_MOUNT_WAIT_SECONDS=10
export IHP_POWER_STATE_SEM_EPOCH=500
export IHP_BOOT_EPOCH=400
export IHP_CUTOVER_REBOOT_WAIT_SECONDS=2
export IHP_CUTOVER_REBOOT_POLL_SECONDS=1
if run_gate; then
  fail "gate should fail when boot is older than power_state sem"
fi
grep -q 'cutover reboot not observed' "${STUBS}/err" \
  || fail "expected cutover timeout message, got: $(cat "${STUBS}/err")"
pass "fails when cutover reboot has not landed"

export IHP_BOOT_EPOCH=600
run_gate || fail "gate should pass when boot is newer than power_state sem"
pass "passes once cutover reboot has landed"
