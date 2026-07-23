#!/usr/bin/env bash
# Acceptance Test: Host Volume Component source/data layout and ownership (ADR-0010)
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts

USER_NAME="${PREFECT_USER:-prefect}"
COMPONENTS_ROOT=/var/lib/prefect/components
DATA_ROOT=/var/lib/prefect/components_data

owner_of() {
  ssh "${SSH_OPTS[@]}" "root@${IP}" "stat -c '%U:%G' '$1'" 2>/dev/null || true
}

must_be_dir() {
  local path="$1"
  if ! ssh "${SSH_OPTS[@]}" "root@${IP}" "test -d '${path}'"; then
    fail "expected directory missing: ${path}"
  fi
}

must_be_file() {
  local path="$1"
  if ! ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f '${path}'"; then
    fail "expected file missing: ${path}"
  fi
}

must_not_exist() {
  local path="$1"
  if ssh "${SSH_OPTS[@]}" "root@${IP}" "test -e '${path}'"; then
    fail "path must not exist: ${path}"
  fi
}

mount_owner="$(owner_of /var/lib/prefect)"
if [[ "${mount_owner}" != "root:root" ]]; then
  fail "/var/lib/prefect owner expected root:root, got '${mount_owner}'"
fi

must_be_dir "${COMPONENTS_ROOT}/network"
must_be_dir "${COMPONENTS_ROOT}/edge"
must_be_file "${COMPONENTS_ROOT}/edge/nginx.conf"
must_be_file "${COMPONENTS_ROOT}/network/setup.sh"
must_be_file "${COMPONENTS_ROOT}/edge/setup.sh"
must_not_exist "${COMPONENTS_ROOT}/edge/certs"

must_be_dir "${DATA_ROOT}/edge/routes"
must_be_dir "${DATA_ROOT}/edge/certs"
must_be_file "${DATA_ROOT}/edge/routes/00-empty.conf"

for path in \
  "${COMPONENTS_ROOT}" \
  "${COMPONENTS_ROOT}/network" \
  "${COMPONENTS_ROOT}/edge" \
  "${DATA_ROOT}" \
  "${DATA_ROOT}/edge" \
  "${DATA_ROOT}/edge/routes" \
  "${DATA_ROOT}/edge/certs"
do
  o="$(owner_of "${path}")"
  if [[ "${o}" != "${USER_NAME}:${USER_NAME}" ]]; then
    fail "${path} owner expected ${USER_NAME}:${USER_NAME}, got '${o}'"
  fi
done

pass "Host Volume Component source/data layout and ownership"
