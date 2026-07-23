#!/usr/bin/env bash
# Edge ACME on-demand runner (systemd user oneshot).
# Empty want-list → success with no CA contact.
# Non-empty → leave issuance to a later drop; do not fail Edge Component Setup.
set -euo pipefail

DATA_ROOT=/var/lib/prefect/components_data/edge
WANT_LIST="${DATA_ROOT}/acme/want-list"

mkdir -p "${DATA_ROOT}/acme" "${DATA_ROOT}/acme-www" "${DATA_ROOT}/certs"
[[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"

mapfile -t names < <(grep -E -v '^[[:space:]]*(#|$)' "${WANT_LIST}" || true)
if ((${#names[@]} == 0)); then
  exit 0
fi

echo "edge-acme: want-list has ${#names[@]} name(s); issuance not implemented yet — skipping CA contact" >&2
exit 0
