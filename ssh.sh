#!/usr/bin/env bash
# Open an interactive SSH session to the Host (root @ Reserved IP).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Requires: terraform, ssh; applied State.
# Optional: SSH_IDENTITY=/path/to/private_key (defaults to ssh agent / default identities).
# Extra args after --env are forwarded to ssh (e.g. ./ssh.sh uptime).
# Usage: ./ssh.sh [--env <slug>] [ssh args...]
# SSH port from lib/ssh.sh (twin of Terraform ssh_port / ADR-0030).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/terraform"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/lib/environment.sh"
# shellcheck source=lib/ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

environment_activate "${STACK_DIR}" "$@" || exit 1
set -- "${ENVIRONMENT_REST[@]+"${ENVIRONMENT_REST[@]}"}"

cd "${STACK_DIR}"

command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

IP="$(terraform output -raw reserved_ip 2>/dev/null || true)"
[[ -n "${IP}" ]] || fail "no reserved_ip output (apply the Stack first)"

SSH_OPTS=(-o "Port=${PREFECT_SSH_PORT}" -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_IDENTITY:-}" ]]; then
  SSH_OPTS+=(-i "${SSH_IDENTITY}" -o IdentitiesOnly=yes)
fi

exec ssh "${SSH_OPTS[@]}" "root@${IP}" "$@"
