#!/usr/bin/env bash
# Unit test: Operator Configuration path require helper (ADR-0037 / ADR-0038).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=operator-configuration.sh
source "${REPO_ROOT}/internals/lib/operator/operator-configuration.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/operator-configuration-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

PUB="${TMP}/id.pub"
PRIV="${TMP}/id"
printf 'ssh-ed25519 AAAA test@host\n' >"${PUB}"
printf 'PRIVATE\n' >"${PRIV}"
chmod 600 "${PRIV}" "${PUB}"

# both: missing fails
unset PROPRAETOR_PUBLIC_KEY_PATH PROPRAETOR_PRIVATE_KEY_PATH
if operator_configuration_require both >/dev/null 2>&1; then
  fail "both must fail when paths unset"
fi
pass "both fails when unset"

# both: happy path absolutizes ~/
HOME="${TMP}/home"
mkdir -p "${HOME}/.ssh"
cp "${PUB}" "${HOME}/.ssh/id.pub"
cp "${PRIV}" "${HOME}/.ssh/id"
export HOME
# shellcheck disable=SC2088  # intentional literal ~/ — require-helper must expand it
export PROPRAETOR_PUBLIC_KEY_PATH='~/.ssh/id.pub'
# shellcheck disable=SC2088  # intentional literal ~/ — require-helper must expand it
export PROPRAETOR_PRIVATE_KEY_PATH='~/.ssh/id'
operator_configuration_require both || fail "both should accept ~/ paths"
[[ "${PROPRAETOR_PUBLIC_KEY_PATH}" == "${HOME}/.ssh/id.pub" ]] \
  || fail "public path should expand ~/"
[[ "${PROPRAETOR_PRIVATE_KEY_PATH}" == "${HOME}/.ssh/id" ]] \
  || fail "private path should expand ~/"
pass "both expands ~/ and accepts readable files"

# relative path fails closed
export PROPRAETOR_PUBLIC_KEY_PATH='relative.pub'
export PROPRAETOR_PRIVATE_KEY_PATH="${PRIV}"
if operator_configuration_require both >/dev/null 2>&1; then
  fail "relative public path must fail closed"
fi
pass "relative path fails closed"

# private-only mode
unset PROPRAETOR_PUBLIC_KEY_PATH
export PROPRAETOR_PRIVATE_KEY_PATH="${PRIV}"
operator_configuration_require private || fail "private should succeed with private only"
pass "private mode requires only private path"

# private mode fails without private
unset PROPRAETOR_PRIVATE_KEY_PATH
if operator_configuration_require private >/dev/null 2>&1; then
  fail "private must fail when unset"
fi
pass "private fails when unset"

# provider credential
unset DIGITALOCEAN_TOKEN
if provider_credential_require >/dev/null 2>&1; then
  fail "provider credential must fail when unset"
fi
export DIGITALOCEAN_TOKEN=tok
provider_credential_require || fail "provider credential should succeed when set"
pass "provider_credential_require"

# apply exports TF_VAR from public path content
export PROPRAETOR_PUBLIC_KEY_PATH="${PUB}"
export PROPRAETOR_PRIVATE_KEY_PATH="${PRIV}"
unset TF_VAR_host_root_ssh_public_key
operator_configuration_require both || fail "require both before export"
operator_configuration_export_host_root_ssh_public_key \
  || fail "export host_root_ssh_public_key should succeed"
[[ "${TF_VAR_host_root_ssh_public_key}" == "ssh-ed25519 AAAA test@host" ]] \
  || fail "TF_VAR should be pubkey content without trailing newline noise; got '${TF_VAR_host_root_ssh_public_key}'"
pass "export host_root_ssh_public_key from public path"

echo "All operator-configuration checks passed."
