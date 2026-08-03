#!/usr/bin/env bash
# Deploy — take a Substrate Host to Deployed without running Stack Apply (ADR-0041).
# Assumes the Stack is Applied and the Host is reachable; waits for IHP Done, then runs
# the Deploy ladder via internals/ensure.sh.
# Environment: omitted / --env default|test → workspace default; --env <slug> otherwise (ADR-0019).
# Usage: ./deploy.sh [--env <slug>]
# Optional: PLATFORM_USER=platform
# Requires: terraform; ssh; Operator Configuration private key path (PROPRAETOR_PRIVATE_KEY_PATH).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${REPO_ROOT}/internals/terraform"
USER_NAME="${PLATFORM_USER:-platform}"
ENSURE="${REPO_ROOT}/internals/ensure.sh"
IHP_DONE="${REPO_ROOT}/internals/host-scripts/wait-until-ihp-done.sh"
# shellcheck source=internals/lib/cli.sh
source "${REPO_ROOT}/internals/lib/cli.sh"
# shellcheck source=internals/lib/environment/environment.sh
source "${REPO_ROOT}/internals/lib/environment/environment.sh"
# shellcheck source=internals/lib/ssh.sh
source "${REPO_ROOT}/internals/lib/ssh.sh"
# shellcheck source=internals/lib/ihp.sh
source "${REPO_ROOT}/internals/lib/ihp.sh"
# shellcheck source=internals/lib/operator/operator-dotenv.sh
source "${REPO_ROOT}/internals/lib/operator/operator-dotenv.sh"
# shellcheck source=internals/lib/operator/operator-configuration.sh
source "${REPO_ROOT}/internals/lib/operator/operator-configuration.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

operator_dotenv_load "${REPO_ROOT}" || exit 1
operator_configuration_require private || exit 1

CLI_env=""
cli_operator_parse CLI -- "$@" || exit 1
environment_activate "${STACK_DIR}" "${CLI_env}" || exit 1

command -v terraform >/dev/null || fail "terraform not found"
command -v ssh >/dev/null || fail "ssh not found"

[[ -f "${ENSURE}" ]] || fail "missing ${ENSURE}"
[[ -f "${IHP_DONE}" ]] || fail "missing ${IHP_DONE}"

host_session_open verify "${STACK_DIR}" || exit 1
IP="$(host_session_ip)"

# Host-local IHP Done gate (Substrate) before the Deploy ladder — ADR-0041 / ADR-0030.
host_wait_until_ihp_done "${IHP_DONE}" "${USER_NAME}"

"${ENSURE}" --env "${PLATFORM_ENV}"

echo "Deployed Environment '${PLATFORM_ENV}' on ${IP}."
