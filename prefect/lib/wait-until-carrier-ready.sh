#!/usr/bin/env bash
# Wait until the public Host carrier is ready for Component Setup.
# Runs on the Host only (as root). Success means Initial Host Provisioning
# outcomes required for Components hold: IHP finished, port floor 80,
# Prefect User present, Host Volume mounted at /var/lib/prefect.
# Usage: PREFECT_USER=prefect ./wait-until-carrier-ready.sh
# Optional: PREFECT_USER (default prefect)
set -euo pipefail

USER_NAME="${PREFECT_USER:-prefect}"

echo "Waiting for Initial Host Provisioning..." >&2
# cloud-init ≥23.4: 0 = clean success, 2 = finished with recoverable errors
# (still "status: done"); 1 = crashed / not finished. Delivery detail — not part
# of this module's public interface. Leave stdout alone so --wait progress dots
# (and the final status line) show the wait is live.
set +e
cloud-init status --wait
rc=$?
set -e
if [[ ${rc} -ne 0 && ${rc} -ne 2 ]]; then
  echo "Initial Host Provisioning wait failed (exit ${rc})" >&2
  exit 1
fi

sysctl --system >/dev/null 2>&1 || true
floor="$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || true)"
if [[ "${floor}" != "80" ]]; then
  echo "net.ipv4.ip_unprivileged_port_start is '${floor}', expected 80 (ADR-0006)" >&2
  exit 1
fi

id "${USER_NAME}" >/dev/null

# findmnt MOUNTPOINT (not -T): -T follows the path and can match / if unmounted.
if ! findmnt --mountpoint /var/lib/prefect >/dev/null 2>&1; then
  echo "Host Volume mount /var/lib/prefect missing" >&2
  exit 1
fi
