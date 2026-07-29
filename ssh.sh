#!/usr/bin/env bash
# Open an interactive SSH session to the Host (root @ Reserved IP).
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Requires: terraform, ssh; applied State.
# Optional: SSH_IDENTITY=/path/to/private_key (defaults to ssh agent / default identities).
# Extra args after --env are forwarded to ssh (e.g. ./ssh.sh uptime).
# Usage: ./ssh.sh [--env <slug>] [ssh args...]
# Host-session: lib/ssh.sh (port twin ADR-0030).
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

command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

host_session_open operator "${STACK_DIR}" || exit 1
host_ssh "$@"
