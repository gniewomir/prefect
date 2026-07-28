#!/usr/bin/env bash
# Fail if the Terraform ssh_port local and shell PREFECT_SSH_PORT drift (ADR-0030).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_MAIN="${REPO_ROOT}/terraform/modules/recreatables/main.tf"
SHELL_SSH="${REPO_ROOT}/lib/ssh.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${TF_MAIN}" ]] || fail "missing ${TF_MAIN}"
[[ -f "${SHELL_SSH}" ]] || fail "missing ${SHELL_SSH}"

tf_port="$(
  awk '/^[[:space:]]*ssh_port[[:space:]]*=/ {
    if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
  }' "${TF_MAIN}"
)"
shell_port="$(
  awk -F= '/^PREFECT_SSH_PORT=/ { print $2; exit }' "${SHELL_SSH}"
)"

[[ -n "${tf_port}" ]] || fail "could not parse ssh_port from ${TF_MAIN}"
[[ -n "${shell_port}" ]] || fail "could not parse PREFECT_SSH_PORT from ${SHELL_SSH}"
[[ "${tf_port}" == "${shell_port}" ]] \
  || fail "SSH port twins drifted: Terraform ssh_port=${tf_port} vs shell PREFECT_SSH_PORT=${shell_port}"

pass "SSH port twins match (${tf_port})"
