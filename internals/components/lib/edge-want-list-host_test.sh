#!/usr/bin/env bash
# Offline tests: Edge want-list placement + shared FQDN reader (#131 / ADR-0023).
# Ambient WANT_LIST / USER_NAME → temp dirs (no SSH / live Host).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=edge-want-list-host.sh
source "${REPO_ROOT}/internals/components/lib/edge-want-list-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/edge-want-list.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

WANT_LIST="${TMP}/acme/want-list"
USER_NAME="offline-test-user"
STAGE="${TMP}/staged-want-list"

# --- install places staged FQDN list into Host want-list ---
mkdir -p "$(dirname "${WANT_LIST}")"
printf '%s\n' 'alpha.example.test' '# comment' 'beta.example.test' >"${STAGE}"
edge_install_want_list "${STAGE}" || fail "edge_install_want_list should succeed"
[[ -f "${WANT_LIST}" ]] || fail "expected WANT_LIST at ${WANT_LIST}"
grep -Fxq 'alpha.example.test' "${WANT_LIST}" || fail "want-list missing alpha.example.test"
grep -Fxq 'beta.example.test' "${WANT_LIST}" || fail "want-list missing beta.example.test"
grep -Fq '# comment' "${WANT_LIST}" || fail "want-list must keep staged comment bytes"
pass "install places staged FQDN list into Host want-list"

# --- install creates parent ACME dir when missing ---
rm -rf "${TMP}/acme"
printf '%s\n' 'gamma.example.test' >"${STAGE}"
edge_install_want_list "${STAGE}" || fail "install should mkdir parent"
[[ -f "${WANT_LIST}" ]] || fail "expected WANT_LIST after mkdir"
grep -Fxq 'gamma.example.test' "${WANT_LIST}" || fail "expected gamma after install"
pass "install creates parent ACME dir when missing"

# --- missing staged file leaves existing want-list; creates empty if absent ---
rm -f "${STAGE}"
printf '%s\n' 'keep.example.test' >"${WANT_LIST}"
edge_install_want_list "${STAGE}" || fail "missing stage should not fail"
grep -Fxq 'keep.example.test' "${WANT_LIST}" || fail "existing want-list must remain when stage missing"
rm -f "${WANT_LIST}"
edge_install_want_list "${STAGE}" || fail "missing stage + missing want-list should not fail"
[[ -f "${WANT_LIST}" ]] || fail "expected empty WANT_LIST created"
[[ ! -s "${WANT_LIST}" ]] || fail "new WANT_LIST should be empty when stage missing"
pass "missing staged file leaves existing want-list; creates empty if absent"

# --- shared reader: non-comment FQDNs one per line ---
printf '%s\n' 'one.example.test' '' '# skip' '  ' 'two.example.test' >"${WANT_LIST}"
got="$(edge_want_list_fqdns)"
expected="$(printf '%s\n' 'one.example.test' 'two.example.test')"
[[ "${got}" == "${expected}" ]] \
  || fail "reader expected one/two FQDNs, got '${got}'"
pass "shared reader prints non-comment want-list FQDNs"

# --- acme-run sources the shared reader (not a private grep) ---
ACME_RUN="${REPO_ROOT}/internals/components/edge/acme-run.sh"
[[ -f "${ACME_RUN}" ]] || fail "missing acme-run.sh"
grep -Eq 'edge_want_list_fqdns' "${ACME_RUN}" \
  || fail "acme-run must iterate via edge_want_list_fqdns"
grep -Eq 'edge-want-list-host\.sh' "${ACME_RUN}" \
  || fail "acme-run must source edge-want-list-host.sh (directly or via a Host lib that does)"
if grep -E "grep .*WANT_LIST|grep -E -v.*want-list" "${ACME_RUN}" >/dev/null; then
  fail "acme-run must not re-parse want-list with its own grep"
fi
pass "acme-run uses shared want-list FQDN reader"

echo "All edge-want-list-host offline tests passed."
