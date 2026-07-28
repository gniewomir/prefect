#!/usr/bin/env bash
# Unit tests: IHP cloud-init Host Volume mount contract (ADR-0031).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WEB_YAML="${REPO_ROOT}/terraform/modules/recreatables/cloud-init/web.yaml"
SCRIPT="${REPO_ROOT}/terraform/modules/recreatables/cloud-init/ensure-host-volume-mount.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${WEB_YAML}" ]] || fail "missing ${WEB_YAML}"
[[ -f "${SCRIPT}" ]] || fail "missing ${SCRIPT}"

grep -q 'prefect-host-volume.service' "${WEB_YAML}" \
  || fail "web.yaml must install prefect-host-volume.service"
pass "installs prefect-host-volume.service"

grep -q 'ensure-host-volume-mount.sh' "${WEB_YAML}" \
  || fail "web.yaml must install ensure-host-volume-mount.sh"
pass "installs ensure-host-volume-mount.sh"

grep -q '99-prefect-host-volume.rules' "${WEB_YAML}" \
  || fail "web.yaml must install udev rule for late attach"
pass "installs udev rule for device-activated start"

grep -q 'tmpfiles.d/prefect-host-volume.conf' "${WEB_YAML}" \
  || fail "web.yaml must install tmpfiles WantedBy symlink recipe"
pass "installs tmpfiles WantedBy symlink recipe"

# Volume wait must not live in runcmd (skipped when scripts_user does not run).
if grep -A20 '^runcmd:' "${WEB_YAML}" | grep -q 'scsi-0DO_Volume'; then
  fail "runcmd must not wait/mount the Host Volume (ADR-0031)"
fi
pass "runcmd does not wait/mount Host Volume"

grep -q 'Restart=on-failure' "${WEB_YAML}" \
  || fail "unit must Restart=on-failure for late attach"
pass "unit uses Restart=on-failure"
