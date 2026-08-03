#!/usr/bin/env bash
# Unit tests: Orphan Reap basename selection (ADR-0041 / #156).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=orphan-reap-host.sh
source "${REPO_ROOT}/internals/host-scripts/lib/orphan-reap-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/orphan-reap.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
WL_ROOT="${TMP}/workloads"
KEEP="${TMP}/keep.txt"
mkdir -p "${WL_ROOT}"

# Empty Host → nothing to reap
: >"${KEEP}"
got="$(orphan_reap_absent_basenames "${WL_ROOT}" "${KEEP}")"
[[ -z "${got}" ]] || fail "empty Host should select nothing, got: ${got}"
pass "empty Host selects no orphans"

# Keep file lists Environment Workloads; Host has keep + orphan + non-Manifest junk
mkdir -p "${WL_ROOT}/keep-me" "${WL_ROOT}/orphan-a" "${WL_ROOT}/orphan-b" "${WL_ROOT}/junk"
printf '{"intent":"run"}\n' >"${WL_ROOT}/keep-me/manifest.json"
printf '{"intent":"run"}\n' >"${WL_ROOT}/orphan-a/manifest.json"
printf 'not-json\n' >"${WL_ROOT}/orphan-b/manifest.json"
printf 'x\n' >"${WL_ROOT}/junk/README.md"
printf 'keep-me\n' >"${KEEP}"

got="$(orphan_reap_absent_basenames "${WL_ROOT}" "${KEEP}" | paste -sd, -)"
[[ "${got}" == "orphan-a,orphan-b" ]] || fail "want orphan-a,orphan-b got '${got}'"
pass "selects Host Manifest basenames absent from keep set"

# All Host Workloads present in Environment → empty selection
printf 'keep-me\norphan-a\norphan-b\n' >"${KEEP}"
got="$(orphan_reap_absent_basenames "${WL_ROOT}" "${KEEP}")"
[[ -z "${got}" ]] || fail "full keep set should select nothing, got: ${got}"
pass "no orphans when keep covers every Host Workload"

echo "All orphan-reap selection checks passed."
