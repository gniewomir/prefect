#!/usr/bin/env bash
# Unit tests: Host Volume mount ensure script (ADR-0031).
# No real mounts — PATH stubs only. Host-only script under test.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../../../.." && pwd)"
SCRIPT="${REPO_ROOT}/internals/terraform/modules/recreatables/cloud-init/render/ensure-host-volume-mount.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${SCRIPT}" ]] || fail "missing script under test: ${SCRIPT}"

STUBS="$(mktemp -d "${TMPDIR:-/tmp}/ensure-host-volume.XXXXXX")"
LOG="${STUBS}/log"
trap 'rm -rf "${STUBS}"' EXIT

DEVICE="${STUBS}/scsi-0DO_Volume_test"
TARGET_DIR="${STUBS}/var-lib-host-volume"
mkdir -p "${TARGET_DIR}"

# --- stubs ---
cat >"${STUBS}/findmnt" <<'EOF'
#!/usr/bin/env bash
# Stub findmnt. Behavior driven by FINDMT_MODE and env files.
set -euo pipefail
mode="${FINDMT_MODE:-}"
mountpoint=""
source_query=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mountpoint)
      mountpoint="${2:-}"
      shift 2
      ;;
    --source|-S)
      source_query=1
      shift 2
      ;;
    -n|-o)
      shift
      if [[ "${1:-}" != --* && "${1:-}" != -* ]]; then
        shift || true
      fi
      ;;
    *)
      shift
      ;;
  esac
done
case "${mode}" in
  missing)
    exit 1
    ;;
  at_target)
    if [[ -n "${mountpoint}" ]]; then
      exit 0
    fi
    if [[ "${source_query}" -eq 1 ]]; then
      exit 0
    fi
    exit 1
    ;;
  foreign)
    if [[ -n "${mountpoint}" ]]; then
      exit 1
    fi
    if [[ "${source_query}" -eq 1 ]]; then
      printf '%s\n' "${FOREIGN_TARGET}"
      exit 0
    fi
    exit 1
    ;;
  foreign_then_ok)
    if [[ -n "${mountpoint}" ]]; then
      if [[ -f "${STUB_STATE}/mount_done" ]]; then
        exit 0
      fi
      exit 1
    fi
    if [[ "${source_query}" -eq 1 ]]; then
      if [[ -f "${STUB_STATE}/umount_done" ]]; then
        exit 0
      fi
      printf '%s\n' "${FOREIGN_TARGET}"
      exit 0
    fi
    exit 1
    ;;
  *)
    echo "findmnt stub: unknown FINDMT_MODE=${mode}" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${STUBS}/findmnt"

cat >"${STUBS}/umount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "umount $*" >>"${STUB_LOG}"
if [[ "${UMOUNT_FAIL:-0}" == "1" ]]; then
  exit 1
fi
touch "${STUB_STATE}/umount_done"
exit 0
EOF
chmod +x "${STUBS}/umount"

cat >"${STUBS}/mount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "mount $*" >>"${STUB_LOG}"
touch "${STUB_STATE}/mount_done"
exit 0
EOF
chmod +x "${STUBS}/mount"

cat >"${STUBS}/mkdir" <<'EOF'
#!/usr/bin/env bash
/bin/mkdir "$@"
EOF
chmod +x "${STUBS}/mkdir"

export STUB_LOG="${LOG}"
export STUB_STATE="${STUBS}/state"
export FOREIGN_TARGET="${STUBS}/mnt-foreign"
mkdir -p "${STUB_STATE}"
: >"${LOG}"
mkdir -p "${FOREIGN_TARGET}"

run_script() {
  rm -f "${STUB_STATE}/umount_done" "${STUB_STATE}/mount_done"
  : >"${LOG}"
  env PATH="${STUBS}:/usr/bin:/bin" \
    HOST_VOLUME_TARGET="${TARGET_DIR}" \
    HOST_VOLUME_DEVICE_WAIT_SECONDS="${HOST_VOLUME_DEVICE_WAIT_SECONDS:-0}" \
    bash "${SCRIPT}" "$@"
}

# --- device missing → fail ---
rm -f "${DEVICE}"
export FINDMT_MODE=missing
if run_script "${DEVICE}" >/dev/null 2>&1; then
  fail "expected failure when device is missing"
fi
pass "fails when by-id device is missing"

# --- already mounted at target → success, no mount/umount ---
: >"${DEVICE}"
export FINDMT_MODE=at_target
run_script "${DEVICE}" || fail "expected success when already mounted at target"
grep -q '^umount ' "${LOG}" && fail "must not umount when already at target"
grep -q '^mount ' "${LOG}" && fail "must not mount when already at target"
pass "no-op when already mounted at canonical path"

# --- foreign mount → umount then mount ---
: >"${DEVICE}"
export FINDMT_MODE=foreign_then_ok
export UMOUNT_FAIL=0
run_script "${DEVICE}" || fail "expected success after reclaim"
grep -q "umount ${FOREIGN_TARGET}" "${LOG}" || fail "expected umount of foreign target"
grep -q "mount ${TARGET_DIR}" "${LOG}" || fail "expected mount of canonical target"
pass "reclaims foreign mount then mounts canonical path"

# --- umount EBUSY → fail (restart will retry) ---
: >"${DEVICE}"
export FINDMT_MODE=foreign
export UMOUNT_FAIL=1
if run_script "${DEVICE}" >/dev/null 2>&1; then
  fail "expected failure when umount is busy"
fi
pass "fails closed on umount EBUSY (no lazy umount)"
