#!/usr/bin/env bash
# Acceptance Test: Host Volume mounted at /var/lib/prefect (ADR-0009)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_host_session

# Standalone runs may skip 60-*; carrier gate waits so findmnt sees post-IHP mount.
wait_until_carrier_ready

# findmnt MOUNTPOINT (not -T): -T follows the path and can match / if unmounted.
if ! host_ssh "findmnt --mountpoint /var/lib/prefect" >/dev/null 2>&1; then
  fail "/var/lib/prefect is not a mounted filesystem"
fi

owner="$(host_ssh "stat -c '%U:%G' /var/lib/prefect" 2>/dev/null || true)"
if [[ "${owner}" != "root:root" ]]; then
  fail "/var/lib/prefect owner expected root:root, got '${owner}'"
fi

pass "Host Volume mounted at /var/lib/prefect"
