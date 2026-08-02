#!/usr/bin/env bash
# Offline Unit Tests: deep Edge Setup outcome (#137).
# Exercises edge_setup through its public interface with temp dirs + stubs —
# no grepping setup.sh call sites; no SSH / live Host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=edge-setup-host.sh
source "${REPO_ROOT}/internals/components/lib/edge-setup-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/edge-setup.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
STATE="${TMP}/state"
mkdir -p "${TMP}/bin" "${STATE}"

# Fast front-door settle for offline tests.
export EDGE_FRONT_DOOR_WAIT_ATTEMPTS=5
export EDGE_FRONT_DOOR_WAIT_SLEEP=0

# --- stubs: curl (front-door), systemctl, runuser, id/getent soft path ---
cat >"${TMP}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# lego download path: refuse network; tests pre-plant lego.
if [[ "$*" == *github.com/go-acme/lego* ]]; then
  echo "stub curl: unexpected lego download" >&2
  exit 1
fi
# edge_wait_front_door: emit http_code via -w
count_file="${STUB_STATE}/curl_count"
n=0
if [[ -f "${count_file}" ]]; then
  n="$(cat "${count_file}")"
fi
n=$((n + 1))
printf '%s\n' "${n}" >"${count_file}"
need="${CURL_SUCCEED_AFTER:-1}"
if [[ "${n}" -ge "${need}" ]]; then
  printf '%s' "404"
  exit 0
fi
exit 7
EOF
chmod +x "${TMP}/bin/curl"

cat >"${TMP}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${STUB_STATE}/systemctl.calls"
# user@ start (session reload)
if [[ "$*" == start\ user@* ]]; then
  exit 0
fi
# edge-pod inactive until first restart (first bring-up must bounce).
if [[ "$*" == *is-active*edge-pod.service* ]]; then
  if [[ -f "${STUB_STATE}/edge-pod-started" ]]; then
    exit 0
  fi
  exit 3
fi
if [[ "$*" == *restart\ edge-pod.service* ]]; then
  : >"${STUB_STATE}/edge-pod-started"
  exit 0
fi
# daemon-reload / reset-failed / enable / restart / is-active / status
if [[ "$*" == *is-active* ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "${TMP}/bin/systemctl"

cat >"${TMP}/bin/runuser" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# runuser -u USER -- env XDG_RUNTIME_DIR=... CMD...
# Drop -u USER -- and env assignments; exec the rest.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    env)
      shift
      while [[ $# -gt 0 && "$1" == *=* ]]; do
        shift
      done
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
EOF
chmod +x "${TMP}/bin/runuser"

export PATH="${TMP}/bin:${PATH}"
export STUB_STATE="${STATE}"

# Session begin without a real Platform User account: point unit dirs at TMP.
quadlet_user_session_begin() {
  HOME_DIR="${TMP}/home"
  UID_NUM="$(id -u)"
  UNIT_DIR="${HOME_DIR}/.config/containers/systemd"
  SYSTEMD_USER_DIR="${HOME_DIR}/.config/systemd/user"
  mkdir -p "${UNIT_DIR}" "${SYSTEMD_USER_DIR}" "${HOME_DIR}/.config"
  export XDG_RUNTIME_DIR="${TMP}/runtime"
  mkdir -p "${XDG_RUNTIME_DIR}"
}

quadlet_user_session_reload() {
  # Skip real user@; daemon-reload via stub systemctl is enough.
  quadlet_user systemctl --user daemon-reload
}

# Minimal Component tree (nginx.conf + acme-run + optional units).
TREE="${TMP}/edge-tree"
mkdir -p "${TREE}/quadlets" "${TREE}/systemd"
printf 'worker_processes 1;\n' >"${TREE}/nginx.conf"
printf '#!/usr/bin/env bash\nexit 0\n' >"${TREE}/acme-run.sh"
chmod a+x "${TREE}/acme-run.sh"
printf '[Container]\nImage=docker.io/library/nginx:alpine\n' >"${TREE}/quadlets/edge-nginx.container"

# Ambient Edge data root (Host Volume substitute).
DATA_ROOT="${TMP}/edge-data"
USER_NAME="$(id -un)"
STAGE="${TMP}/staged-want-list"
printf '%s\n' 'alpha.example.test' '# comment' 'beta.example.test' >"${STAGE}"

# Pre-plant lego at the expected version so Setup never hits the network.
mkdir -p "${DATA_ROOT}/acme/bin"
cat >"${DATA_ROOT}/acme/bin/lego" <<'EOF'
#!/usr/bin/env bash
echo "lego version 5.3.1"
EOF
chmod +x "${DATA_ROOT}/acme/bin/lego"

# --- success: Domains present + units installed + front door answers ---
: >"${STATE}/curl_count"
: >"${STATE}/systemctl.calls"
export CURL_SUCCEED_AFTER=1
edge_setup "${TREE}" "${STAGE}" || fail "edge_setup should succeed"

WANT_LIST="${DATA_ROOT}/acme/want-list"
[[ -f "${WANT_LIST}" ]] || fail "expected Host want-list after Setup"
grep -Fxq 'alpha.example.test' "${WANT_LIST}" || fail "want-list missing alpha.example.test"
grep -Fxq 'beta.example.test' "${WANT_LIST}" || fail "want-list missing beta.example.test"

[[ -f "${DATA_ROOT}/domains/alpha.example.test.conf" ]] \
  || fail "expected Domain front for alpha.example.test"
[[ -f "${DATA_ROOT}/domains/beta.example.test.conf" ]] \
  || fail "expected Domain front for beta.example.test"
[[ -f "${DATA_ROOT}/certs/alpha.example.test/fullchain.pem" ]] \
  || fail "expected placeholder fullchain for alpha"
[[ -f "${DATA_ROOT}/certs/alpha.example.test/privkey.pem" ]] \
  || fail "expected placeholder privkey for alpha"

[[ -f "${UNIT_DIR}/edge-nginx.container" ]] \
  || fail "expected Component quadlet installed under UNIT_DIR"

grep -Fq 'restart edge-pod.service' "${STATE}/systemctl.calls" \
  || fail "expected edge-pod restart"
grep -Fq 'enable --now edge-acme.timer' "${STATE}/systemctl.calls" \
  || fail "expected ACME timer enable"
grep -Fq 'restart edge-acme.service' "${STATE}/systemctl.calls" \
  || fail "expected ACME oneshot restart"
pass "edge_setup succeeds: Domains present, units active path, front door answers"

# --- gathers Intent-run Route Declarations from Workload SoT (ADR-0040) ---
: >"${STATE}/curl_count"
: >"${STATE}/systemctl.calls"
export CURL_SUCCEED_AFTER=1
DATA_ROOT="${TMP}/edge-data"
WORKLOADS_ROOT="$(dirname "${DATA_ROOT}")/workloads"
mkdir -p "${WORKLOADS_ROOT}/alpha/routes"
printf '%s\n' '{"intent":"run"}' >"${WORKLOADS_ROOT}/alpha/manifest.json"
printf '%s\n' 'location /gather { return 200 "g"; }' \
  >"${WORKLOADS_ROOT}/alpha/routes/alpha.example.test.conf"
# Prior Edge install must be replaced from SoT on gather.
printf '%s\n' '# stale' >"${DATA_ROOT}/routes/stale--alpha.example.test.conf"
edge_setup "${TREE}" "${STAGE}" || fail "edge_setup with Workload SoT should succeed"
[[ -f "${DATA_ROOT}/routes/alpha--alpha.example.test.conf" ]] \
  || fail "edge_setup must fulfill Intent-run Route from Workload SoT"
grep -Fq 'location /gather' "${DATA_ROOT}/routes/alpha--alpha.example.test.conf" \
  || fail "fulfilled Route must keep SoT bytes"
[[ ! -f "${DATA_ROOT}/routes/stale--alpha.example.test.conf" ]] \
  || fail "edge_setup gather must drop orphan Edge Route installs"
pass "edge_setup gathers Intent-run Route Declarations from Workload SoT"

# --- unchanged gather skips front-door bounce (Setup noop for Routes) ---
: >"${STATE}/curl_count"
: >"${STATE}/systemctl.calls"
export CURL_SUCCEED_AFTER=1
# Pod already active from prior Setup; SoT unchanged → EDGE_ROUTES_CHANGED=0.
edge_setup "${TREE}" "${STAGE}" || fail "edge_setup noop re-run should succeed"
if grep -Fq 'restart edge-pod.service' "${STATE}/systemctl.calls"; then
  fail "unchanged gather must not restart edge-pod"
fi
if grep -Fq 'restart edge-acme.service' "${STATE}/systemctl.calls"; then
  fail "unchanged gather must not restart edge-acme"
fi
grep -Fq 'is-active edge-pod.service' "${STATE}/systemctl.calls" \
  || fail "noop re-run must still assert edge-pod is active"
pass "edge_setup skips bounce when Route gather is unchanged"

# --- fail closed when front door never answers ---
: >"${STATE}/curl_count"
: >"${STATE}/systemctl.calls"
export CURL_SUCCEED_AFTER=999
export EDGE_FRONT_DOOR_WAIT_ATTEMPTS=3
# Fresh data root so want-list/fronts still reconcile; outcome fails on wait.
DATA_ROOT="${TMP}/edge-data-fail"
mkdir -p "${DATA_ROOT}/acme/bin"
cp "${TMP}/edge-data/acme/bin/lego" "${DATA_ROOT}/acme/bin/lego"
if edge_setup "${TREE}" "${STAGE}" 2>"${STATE}/setup.err"; then
  fail "edge_setup should fail when front door never answers"
fi
grep -Fq 'did not answer on :80' "${STATE}/setup.err" \
  || fail "expected :80 timeout in Setup failure, got: $(cat "${STATE}/setup.err")"
# Domain presence still reconciled before wait (implementation ordering).
[[ -f "${DATA_ROOT}/domains/alpha.example.test.conf" ]] \
  || fail "Domain fronts should exist even when wait fails"
pass "edge_setup fails closed when front door never answers"

# --- staging pathname is Setup-seam only (not every helper's public interface) ---
for helper in \
  edge-want-list-host.sh \
  edge-domain-fronts-host.sh \
  edge-front-door-host.sh \
  edge-routes-host.sh; do
  path="${REPO_ROOT}/internals/components/lib/${helper}"
  [[ -f "${path}" ]] || fail "missing ${helper}"
  # Helpers must not require a staged want-list path argument in their public surface.
  if grep -E 'staged_want_list|/tmp/platform-acme-want-list' "${path}" >/dev/null; then
    fail "${helper} must not thread staging pathname as public interface"
  fi
done
# edge_install_want_list keeps a staged_path arg (install seam); reader does not.
grep -Eq '^edge_install_want_list\(\)' \
  "${REPO_ROOT}/internals/components/lib/edge-want-list-host.sh" \
  || fail "edge_install_want_list should remain the install seam"
grep -Eq '^edge_want_list_fqdns\(\)' \
  "${REPO_ROOT}/internals/components/lib/edge-want-list-host.sh" \
  || fail "shared FQDN reader must remain for Route/ACME gating"
pass "staging pathname stays at Setup/install seam; helpers keep ambient WANT_LIST"

# --- thin setup.sh calls deep edge_setup (not a caller checklist) ---
SETUP="${REPO_ROOT}/internals/components/edge/setup.sh"
[[ -f "${SETUP}" ]] || fail "missing setup.sh"
grep -Fq 'edge-setup-host.sh' "${SETUP}" \
  || fail "setup.sh must source edge-setup-host.sh"
grep -Eq 'edge_setup ' "${SETUP}" \
  || fail "setup.sh must call edge_setup"
# Implementation steps must not remain as a public checklist in setup.sh.
for step in edge_install_want_list edge_plant_placeholder_pems edge_reconcile_domain_fronts edge_gather_workload_routes edge_wait_front_door; do
  if grep -Eq "${step}" "${SETUP}"; then
    fail "setup.sh must not expose ${step} as a caller checklist (lives in edge_setup)"
  fi
done
pass "setup.sh is thin: ambient + edge_setup only"

echo "All edge-setup-host offline tests passed."
