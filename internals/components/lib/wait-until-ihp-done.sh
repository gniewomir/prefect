#!/usr/bin/env bash
# Wait until Initial Host Provisioning Done (IHP Done) for Component Setup.
# Runs on the Host only (as root). Success means Initial Host Provisioning
# outcomes required for Components hold: IHP finished, port floor 80,
# Platform User present, Host Volume mounted at /var/lib/host-volume.
# Usage: PLATFORM_USER=platform ./wait-until-ihp-done.sh
# Optional: PLATFORM_USER (default platform)
set -euo pipefail

USER_NAME="${PLATFORM_USER:-platform}"

echo "Waiting for Initial Host Provisioning..." >&2
# cloud-init ≥23.4: 0 = clean success; non-zero includes 2 = finished with
# recoverable errors (still "status: done") and 1 = crashed / not finished.
# Require clean success for now so degradations surface immediately; may relax
# later. Delivery detail — not part of this module's public interface. Leave
# stdout alone so --wait progress dots (and the final status line) show the
# wait is live.
set +e
cloud-init status --wait
rc=$?
set -e
if [[ ${rc} -ne 0 ]]; then
  echo "Initial Host Provisioning wait failed (exit ${rc})" >&2
  cloud-init status --long >&2 || true
  exit 1
fi

sysctl --system >/dev/null 2>&1 || true
floor="$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || true)"
if [[ "${floor}" != "80" ]]; then
  echo "net.ipv4.ip_unprivileged_port_start is '${floor}', expected 80 (ADR-0006)" >&2
  exit 1
fi

id "${USER_NAME}" >/dev/null

# Host Volume mount wait budget must stay aligned with host-volume.service
# start-limit window (ADR-0031). Override only in tests.
WAIT_SECONDS="${HOST_VOLUME_MOUNT_WAIT_SECONDS:-300}"
POLL_SECONDS="${HOST_VOLUME_MOUNT_POLL_SECONDS:-2}"
deadline=$((SECONDS + WAIT_SECONDS))
# findmnt MOUNTPOINT (not -T): -T follows the path and can match / if unmounted.
while ! findmnt --mountpoint /var/lib/host-volume >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    echo "Host Volume mount /var/lib/host-volume missing after ${WAIT_SECONDS}s (see host-volume.service)" >&2
    exit 1
  fi
  sleep "${POLL_SECONDS}"
done
