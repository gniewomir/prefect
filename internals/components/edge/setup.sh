#!/usr/bin/env bash
# Component Setup for the Edge.
# Idempotent: safe to re-run. Success means this Component is in the correct state.
# Runs on the Host only (no Stack discovery / SSH). Invoked by ensure-components.sh.
# Domain presence + ready front door: deep edge_setup (#137).
set -euo pipefail

USER_NAME="${PLATFORM_USER:-platform}"
SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../host-scripts/lib/edge-setup-host.sh
source /var/lib/host-volume/internals/host-scripts/lib/edge-setup-host.sh

# Staged want-list handoff from ensure-components (ADR-0023 / #131).
# Staging pathname enters only at this seam — not every Edge helper's interface.
edge_setup "${SRC}" /tmp/platform-acme-want-list
