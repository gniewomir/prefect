#!/usr/bin/env bash
# Open an interactive SSH session to the Host (root @ Reserved IP).
# Requires: terraform, ssh; applied State.
# Optional: SSH_IDENTITY=/path/to/private_key (defaults to ssh agent / default identities).
# Extra args are forwarded to ssh (e.g. ./ssh.sh uptime).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
cd "${STACK_DIR}"

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (apply the Stack first)"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

exec ssh "${SSH_OPTS[@]}" "root@${IP}" "$@"
