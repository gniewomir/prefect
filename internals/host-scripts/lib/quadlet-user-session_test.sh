#!/usr/bin/env bash
# Offline tests: Platform User session helpers must not inherit root XDG_RUNTIME_DIR.
# Repro: root SSH often has XDG_RUNTIME_DIR=/run/user/0; passing that to platform
# yields "Failed to connect to user scope bus … Operation not permitted".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=quadlet-user-session.sh
source "${REPO_ROOT}/internals/host-scripts/lib/quadlet-user-session.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/quadlet-user-session.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/bin" "${TMP}/home" "${TMP}/run/user/1000"

# Soft-path stubs: pretend Platform User uid 1000 with HOME under TMP.
cat >"${TMP}/bin/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == "-u" ]]; then
  echo 1000
  exit 0
fi
# id USERNAME existence check
exit 0
EOF
chmod +x "${TMP}/bin/id"

cat >"${TMP}/bin/getent" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'platform:x:1000:1000::%s:/bin/bash\n' "${TMP}/home"
EOF
chmod +x "${TMP}/bin/getent"

# Capture XDG_RUNTIME_DIR that quadlet_user passes through env.
cat >"${TMP}/bin/runuser" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
if [[ "${1-}" == env ]]; then
  shift
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    printf '%s\n' "$1"
    shift
  done
  exit 0
fi
exit 0
EOF
chmod +x "${TMP}/bin/runuser"

export PATH="${TMP}/bin:${PATH}"
USER_NAME=platform

# Simulate root SSH session exporting root's runtime dir (the live prod failure mode).
export XDG_RUNTIME_DIR=/run/user/0

quadlet_user_session_begin
[[ "${XDG_RUNTIME_DIR}" == "/run/user/1000" ]] \
  || fail "begin must set XDG_RUNTIME_DIR to Platform User runtime, got '${XDG_RUNTIME_DIR}'"
[[ "${UID_NUM}" == "1000" ]] || fail "UID_NUM want 1000, got '${UID_NUM}'"
pass "quadlet_user_session_begin exports Platform User XDG_RUNTIME_DIR"

got="$(quadlet_user true)"
echo "${got}" | grep -Fxq 'XDG_RUNTIME_DIR=/run/user/1000' \
  || fail "quadlet_user must pass Platform User XDG, got: ${got}"
if echo "${got}" | grep -Fq 'XDG_RUNTIME_DIR=/run/user/0'; then
  fail "quadlet_user must not pass root XDG_RUNTIME_DIR=/run/user/0"
fi
pass "quadlet_user does not inherit root XDG_RUNTIME_DIR"

# edge_setup_pre_workloads must ensure session before is-active (source contract).
PRE_FN="${REPO_ROOT}/internals/host-scripts/lib/edge-setup-host.sh"
grep -A20 '^edge_setup_pre_workloads()' "${PRE_FN}" | grep -Fq 'quadlet_user_session_begin' \
  || fail "pre-workloads must call quadlet_user_session_begin before is-active"
# After begin, XDG must already be platform-scoped — covered above; also require
# that begin is the documented exporter (not only reload).
grep -Eq 'export XDG_RUNTIME_DIR=' "${REPO_ROOT}/internals/host-scripts/lib/quadlet-user-session.sh" \
  || fail "session helper must export XDG_RUNTIME_DIR"
pass "pre-workloads / begin contract covers bus before is-active"

echo "All quadlet-user-session offline tests passed."
