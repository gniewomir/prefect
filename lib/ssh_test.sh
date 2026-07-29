#!/usr/bin/env bash
# Host-session seam (lib/ssh.sh). PATH stubs for terraform/ssh/scp/ssh-keygen — no cloud.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ssh.sh
source "${REPO_ROOT}/lib/ssh.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssh-session-test.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

# --- Seam 1: bind → IP accessor ---
host_session_bind verify "203.0.113.10" || fail "bind verify should succeed"
got="$(host_session_ip)" || fail "host_session_ip should succeed after bind"
[[ "${got}" == "203.0.113.10" ]] || fail "host_session_ip: want 203.0.113.10, got '${got}'"
pass "bind verify → host_session_ip returns bound Reserved IP"

# --- Seam 2: open → terraform Reserved IP ---
STACK_DIR="${TMP_DIR}/stack"
mkdir -p "${STACK_DIR}"
mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TERRAFORM_CALLS}"
if [[ "${1-}" == output && "${2-}" == -raw && "${3-}" == reserved_ip ]]; then
  printf '%s\n' "198.51.100.20"
  exit 0
fi
echo "unexpected terraform args: $*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/terraform"
export PATH="${TMP_DIR}/bin:${PATH}"
export TERRAFORM_CALLS="${TMP_DIR}/terraform.calls"
: >"${TERRAFORM_CALLS}"

host_session_open verify "${STACK_DIR}" || fail "open verify should succeed with terraform reserved_ip"
got="$(host_session_ip)" || fail "host_session_ip should succeed after open"
[[ "${got}" == "198.51.100.20" ]] || fail "open: want 198.51.100.20, got '${got}'"
grep -Fq "output -raw reserved_ip" "${TERRAFORM_CALLS}" \
  || fail "open must run terraform output -raw reserved_ip"
pass "open verify → host_session_ip from terraform reserved_ip"

# Empty reserved_ip fails closed
cat >"${TMP_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == output && "${2-}" == -raw && "${3-}" == reserved_ip ]]; then
  printf '\n'
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/bin/terraform"
if host_session_open verify "${STACK_DIR}" >/dev/null 2>&1; then
  fail "open should fail when reserved_ip is empty"
fi
pass "open fails closed on empty reserved_ip"

# --- Seam 3: verify profile host_ssh / host_scp argv ---
# Reset session from empty-open attempt: re-bind for runner tests.
host_session_bind verify "203.0.113.50" || fail "re-bind for runner tests"

cat >"${TMP_DIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SSH_CALLS}"
exit 0
EOF
cat >"${TMP_DIR}/bin/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SCP_CALLS}"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/ssh" "${TMP_DIR}/bin/scp"
export SSH_CALLS="${TMP_DIR}/ssh.calls"
export SCP_CALLS="${TMP_DIR}/scp.calls"
: >"${SSH_CALLS}"
: >"${SCP_CALLS}"

VERIFY_SSH_IDENTITY="${TMP_DIR}/verify_key"
touch "${VERIFY_SSH_IDENTITY}"
export VERIFY_SSH_IDENTITY

host_ssh true || fail "host_ssh should invoke stub ssh"
ssh_line="$(cat "${SSH_CALLS}")"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o Port=${PREFECT_SSH_PORT}" \
  || fail "verify host_ssh missing Port=${PREFECT_SSH_PORT}; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o BatchMode=yes" \
  || fail "verify host_ssh missing BatchMode=yes; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o StrictHostKeyChecking=accept-new" \
  || fail "verify host_ssh missing StrictHostKeyChecking; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o ConnectTimeout=10" \
  || fail "verify host_ssh missing ConnectTimeout; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o PreferredAuthentications=publickey" \
  || fail "verify host_ssh missing PreferredAuthentications; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-i ${VERIFY_SSH_IDENTITY}" \
  || fail "verify host_ssh missing -i identity; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "root@203.0.113.50" \
  || fail "verify host_ssh missing root@IP; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Eq '(^| )true( |$)' \
  || fail "verify host_ssh missing remote command true; got: ${ssh_line}"
pass "verify host_ssh argv (port, BatchMode, identity, root@IP)"

touch "${TMP_DIR}/local.txt"
: >"${SCP_CALLS}"
host_scp "${TMP_DIR}/local.txt" /tmp/remote.txt || fail "host_scp should invoke stub scp"
scp_line="$(cat "${SCP_CALLS}")"
printf '%s\n' "${scp_line}" | grep -Fq -- "-o Port=${PREFECT_SSH_PORT}" \
  || fail "verify host_scp missing Port; got: ${scp_line}"
printf '%s\n' "${scp_line}" | grep -Fq -- "-o BatchMode=yes" \
  || fail "verify host_scp missing BatchMode; got: ${scp_line}"
printf '%s\n' "${scp_line}" | grep -Fq -- "-i ${VERIFY_SSH_IDENTITY}" \
  || fail "verify host_scp missing -i identity; got: ${scp_line}"
printf '%s\n' "${scp_line}" | grep -Fq -- "${TMP_DIR}/local.txt" \
  || fail "verify host_scp missing local path; got: ${scp_line}"
printf '%s\n' "${scp_line}" | grep -Fq -- "root@203.0.113.50:/tmp/remote.txt" \
  || fail "verify host_scp missing root@IP:remote; got: ${scp_line}"
pass "verify host_scp argv (opts, identity, root@IP:path)"

# --- Seam 4: operator profile opts ---
unset VERIFY_SSH_IDENTITY
SSH_IDENTITY="${TMP_DIR}/operator_key"
touch "${SSH_IDENTITY}"
export SSH_IDENTITY
host_session_bind operator "203.0.113.60" || fail "bind operator should succeed"
: >"${SSH_CALLS}"
host_ssh uptime || fail "operator host_ssh should invoke stub ssh"
ssh_line="$(cat "${SSH_CALLS}")"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o Port=${PREFECT_SSH_PORT}" \
  || fail "operator host_ssh missing Port; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "-o StrictHostKeyChecking=accept-new" \
  || fail "operator host_ssh missing StrictHostKeyChecking; got: ${ssh_line}"
if printf '%s\n' "${ssh_line}" | grep -Fq -- "BatchMode"; then
  fail "operator host_ssh must not set BatchMode; got: ${ssh_line}"
fi
if printf '%s\n' "${ssh_line}" | grep -Fq -- "ConnectTimeout"; then
  fail "operator host_ssh must not set ConnectTimeout; got: ${ssh_line}"
fi
printf '%s\n' "${ssh_line}" | grep -Fq -- "-i ${SSH_IDENTITY}" \
  || fail "operator host_ssh missing -i SSH_IDENTITY; got: ${ssh_line}"
printf '%s\n' "${ssh_line}" | grep -Fq -- "root@203.0.113.60" \
  || fail "operator host_ssh missing root@IP; got: ${ssh_line}"
pass "operator host_ssh argv (no BatchMode, SSH_IDENTITY)"

# --- Seam 5: fail closed before open/bind (fresh process — no ambient session) ---
if bash -c "source '${REPO_ROOT}/lib/ssh.sh'; host_session_ip" >/dev/null 2>&1; then
  fail "host_session_ip should fail with no session"
fi
pass "host_session_ip fails closed with no session"

if bash -c "source '${REPO_ROOT}/lib/ssh.sh'; host_ssh true" >/dev/null 2>&1; then
  fail "host_ssh should fail with no session"
fi
pass "host_ssh fails closed with no session"

if bash -c "source '${REPO_ROOT}/lib/ssh.sh'; host_scp /tmp/a /tmp/b" >/dev/null 2>&1; then
  fail "host_scp should fail with no session"
fi
pass "host_scp fails closed with no session"

# --- Seam 6: forget stays explicit ---
cat >"${TMP_DIR}/bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${SSH_KEYGEN_CALLS}"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/ssh-keygen"
export SSH_KEYGEN_CALLS="${TMP_DIR}/ssh-keygen.calls"
: >"${SSH_KEYGEN_CALLS}"

# Restore terraform stub for open
cat >"${TMP_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == output && "${2-}" == -raw && "${3-}" == reserved_ip ]]; then
  printf '%s\n' "203.0.113.77"
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/bin/terraform"

host_session_bind verify "203.0.113.77" || fail "bind for forget test"
host_session_open verify "${STACK_DIR}" || fail "open for forget test"
if [[ -s "${SSH_KEYGEN_CALLS}" ]]; then
  fail "open/bind must not call ssh-keygen; got: $(cat "${SSH_KEYGEN_CALLS}")"
fi
pass "open/bind do not forget known_hosts"

: >"${SSH_KEYGEN_CALLS}"
prefect_ssh_forget_host "203.0.113.77" || fail "prefect_ssh_forget_host should succeed"
grep -Fq -- "-R 203.0.113.77" "${SSH_KEYGEN_CALLS}" \
  || fail "forget must clear bare IP; got: $(cat "${SSH_KEYGEN_CALLS}")"
grep -Fq -- "-R [203.0.113.77]:${PREFECT_SSH_PORT}" "${SSH_KEYGEN_CALLS}" \
  || fail "forget must clear [ip]:port; got: $(cat "${SSH_KEYGEN_CALLS}")"
pass "prefect_ssh_forget_host clears bare IP and [ip]:port"




