#!/usr/bin/env bash
# Offline tests: Edge front-door readiness/reload seam (#134).
# PATH stubs for curl / systemctl — no SSH / live Host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=edge-front-door-host.sh
source "${REPO_ROOT}/internals/components/lib/edge-front-door-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/edge-front-door.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
STATE="${TMP}/state"
mkdir -p "${TMP}/bin" "${STATE}"

# Fast settle for offline tests (production defaults remain in the lib).
export EDGE_FRONT_DOOR_WAIT_ATTEMPTS=5
export EDGE_FRONT_DOOR_WAIT_SLEEP=0

cat >"${TMP}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count_file="${STUB_STATE}/curl_count"
n=0
if [[ -f "${count_file}" ]]; then
  n="$(cat "${count_file}")"
fi
n=$((n + 1))
printf '%s\n' "${n}" >"${count_file}"
need="${CURL_SUCCEED_AFTER:-1}"
# Emit http_code via -w when requested (match edge_wait_front_door argv).
if [[ "${n}" -ge "${need}" ]]; then
  printf '%s' "404"
  exit 0
fi
# Fail like a refused connection (no http_code).
exit 7
EOF
chmod +x "${TMP}/bin/curl"

cat >"${TMP}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${STUB_STATE}/systemctl.calls"
# --quiet is-active edge-pod.service
if [[ "$*" == *is-active*edge-pod.service* ]]; then
  if [[ "${EDGE_POD_ACTIVE:-1}" == "1" ]]; then
    exit 0
  fi
  exit 3
fi
# restart edge-pod.service
if [[ "$*" == *restart*edge-pod.service* ]]; then
  printf 'restarted\n' >>"${STUB_STATE}/restarts"
  exit 0
fi
exit 0
EOF
chmod +x "${TMP}/bin/systemctl"

export PATH="${TMP}/bin:${PATH}"
export STUB_STATE="${STATE}"
# Reload path uses Platform User == current user so it drives systemctl --user (not quadlet_user).
USER_NAME="$(id -un)"
export USER_NAME
export XDG_RUNTIME_DIR="${TMP}/runtime"
mkdir -p "${XDG_RUNTIME_DIR}"

# --- wait succeeds once curl returns an HTTP status ---
: >"${STATE}/curl_count"
export CURL_SUCCEED_AFTER=3
edge_wait_front_door || fail "edge_wait_front_door should succeed after curl answers"
count="$(cat "${STATE}/curl_count")"
[[ "${count}" -ge 3 ]] || fail "expected at least 3 curl attempts, got ${count}"
pass "wait succeeds once Host :80 returns an HTTP status"

# --- wait fails closed when :80 never answers ---
: >"${STATE}/curl_count"
export CURL_SUCCEED_AFTER=999
export EDGE_FRONT_DOOR_WAIT_ATTEMPTS=3
if edge_wait_front_door 2>"${STATE}/wait.err"; then
  fail "edge_wait_front_door should fail when :80 never answers"
fi
grep -Fq 'did not answer on :80' "${STATE}/wait.err" \
  || fail "expected :80 timeout message, got: $(cat "${STATE}/wait.err")"
pass "wait fails closed when Host :80 never answers"

# --- reload restarts active edge-pod then waits for :80 ---
: >"${STATE}/curl_count"
: >"${STATE}/systemctl.calls"
: >"${STATE}/restarts"
export CURL_SUCCEED_AFTER=1
export EDGE_FRONT_DOOR_WAIT_ATTEMPTS=5
export EDGE_POD_ACTIVE=1
edge_reload_front_door || fail "edge_reload_front_door should succeed"
grep -Fq 'restarted' "${STATE}/restarts" || fail "expected edge-pod restart"
grep -Fq 'is-active' "${STATE}/systemctl.calls" || fail "expected is-active check"
pass "reload restarts active edge-pod then waits for :80"

# --- reload is a no-op success when edge-pod is not active ---
: >"${STATE}/systemctl.calls"
: >"${STATE}/restarts"
export EDGE_POD_ACTIVE=0
edge_reload_front_door || fail "inactive edge-pod should not fail reload"
[[ ! -s "${STATE}/restarts" ]] || fail "inactive edge-pod must not restart"
pass "reload no-ops when edge-pod is not active"

# --- callers share the seam (no local :80 poll loops) ---
SETUP="${REPO_ROOT}/internals/components/edge/setup.sh"
ACME_RUN="${REPO_ROOT}/internals/components/edge/acme-run.sh"
ROUTES="${REPO_ROOT}/internals/components/lib/edge-routes-host.sh"
[[ -f "${SETUP}" && -f "${ACME_RUN}" && -f "${ROUTES}" ]] || fail "missing Setup/ACME/routes sources"

grep -Fq 'edge-front-door-host.sh' "${SETUP}" \
  || fail "Edge Setup must source edge-front-door-host.sh"
grep -Eq 'edge_wait_front_door' "${SETUP}" \
  || fail "Edge Setup must settle via edge_wait_front_door"
if grep -E 'for _ in \$\(seq|curl .*127\.0\.0\.1' "${SETUP}" >/dev/null; then
  fail "Edge Setup must not keep a local :80 poll loop"
fi
pass "Edge Setup uses shared front-door wait"

grep -Fq 'edge-front-door-host.sh' "${ACME_RUN}" \
  || fail "acme-run must source edge-front-door-host.sh"
grep -Eq 'edge_reload_front_door' "${ACME_RUN}" \
  || fail "acme-run must settle via edge_reload_front_door"
if grep -E 'for _ in \$\(seq|curl .*127\.0\.0\.1' "${ACME_RUN}" >/dev/null; then
  fail "acme-run must not keep a local :80 poll loop"
fi
pass "ACME uses shared front-door reload"

grep -Fq 'edge-front-door-host.sh' "${ROUTES}" \
  || fail "edge-routes-host must source edge-front-door-host.sh"
grep -Eq 'edge_reload_front_door' "${ROUTES}" \
  || fail "edge-routes-host must call edge_reload_front_door for Route reload"
if grep -E 'curl .*127\.0\.0\.1' "${ROUTES}" >/dev/null; then
  fail "edge-routes-host must not own the :80 poll loop"
fi
pass "Route reload uses shared front-door reload"

echo "All edge-front-door-host offline tests passed."
