#!/usr/bin/env bash
# Seam: ensure_stack_applied — Apply when not Applied; reuse when Applied.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
export REPO_ROOT="${REAL_ROOT}"
# shellcheck source=lib.sh
source "${CASE_DIR}/lib.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export PLATFORM_ENV=test
export DIGITALOCEAN_TOKEN=test-token

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ensure-applied.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
RECORD="${TMP}/apply.record"

cat >"${TMP}/apply.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'apply\n' >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${RECORD}"
exit 0
EOF
chmod +x "${TMP}/apply.sh"

# Helper invokes "\${REPO_ROOT}/apply.sh" — point at the stub.
export REPO_ROOT="${TMP}"

# --- already Applied: Reserved IP + Host present → no Apply ---
stack_reserved_ip() { printf '%s\n' '203.0.113.10'; }
provider_host_by_name_json() { printf '%s\n' '{"id":42,"name":"propraetor-test-web"}'; }
: >"${RECORD}"
unset IP || true
ensure_stack_applied
[[ "${IP}" == "203.0.113.10" ]] || fail "already-Applied path must export Reserved IP"
[[ ! -s "${RECORD}" ]] || fail "already-Applied path must not call Apply"
pass "already Applied reuses Reserved IP without Apply"

# --- Parked: Reserved IP present, Host absent → Apply ---
stack_reserved_ip() { printf '%s\n' '203.0.113.20'; }
provider_host_by_name_json() { printf '%s\n' ''; }
: >"${RECORD}"
unset IP || true
ensure_stack_applied
[[ "${IP}" == "203.0.113.20" ]] || fail "Parked→Apply path must export Reserved IP"
grep -Fxq 'apply' "${RECORD}" || fail "Parked path must call Apply"
grep -Fq 'args=--yes --env test' "${RECORD}" \
  || fail "Apply must receive --yes --env ${PLATFORM_ENV}"
pass "Parked Stack triggers Apply"

# --- fresh / empty: no reserved_ip until after Apply ---
# apply.sh stub plants a flag; reserved_ip appears only after that (subshell-safe).
cat >"${TMP}/apply.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'apply\n' >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${RECORD}"
: >"${TMP}/applied.flag"
exit 0
EOF
chmod +x "${TMP}/apply.sh"
rm -f "${TMP}/applied.flag"
stack_reserved_ip() {
  [[ -f "${TMP}/applied.flag" ]] || return 1
  printf '%s\n' '203.0.113.30'
}
provider_host_by_name_json() { printf '%s\n' ''; }
: >"${RECORD}"
unset IP || true
ensure_stack_applied
[[ "${IP}" == "203.0.113.30" ]] || fail "fresh→Apply path must export post-Apply Reserved IP"
grep -Fxq 'apply' "${RECORD}" || fail "fresh path must call Apply"
pass "fresh Stack triggers Apply and exports reserved_ip"

# --- Apply succeeds but still no reserved_ip → fail closed ---
stack_reserved_ip() { return 1; }
provider_host_by_name_json() { printf '%s\n' ''; }
: >"${RECORD}"
unset IP || true
if ( ensure_stack_applied >/dev/null 2>&1 ); then
  fail "missing reserved_ip after Apply must fail"
fi
pass "missing reserved_ip after Apply fails closed"

echo "All ensure_stack_applied checks passed."
