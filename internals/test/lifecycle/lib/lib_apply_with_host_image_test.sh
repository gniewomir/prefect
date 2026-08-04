#!/usr/bin/env bash
# Seam: apply_with_host_image — TF_VAR_host_image for one Apply only (#64 / ADR-0037).
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
export REPO_ROOT="${REAL_ROOT}"
# shellcheck source=lib.sh
source "${CASE_DIR}/lib.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export PLATFORM_ENV=test
export DIGITALOCEAN_TOKEN=test-token

TMP="$(mktemp -d "${TMPDIR:-/tmp}/apply-host-image.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
RECORD="${TMP}/apply.record"

cat >"${TMP}/apply.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'TF_VAR_host_image=%s\n' "\${TF_VAR_host_image-}" >>"${RECORD}"
printf 'args=%s\n' "\$*" >>"${RECORD}"
exit "\${APPLY_STUB_RC:-0}"
EOF
chmod +x "${TMP}/apply.sh"

# Helper invokes "\${REPO_ROOT}/apply.sh" — point at the stub for the inject.
export REPO_ROOT="${TMP}"
: >"${RECORD}"
PARENT_BEFORE="${TF_VAR_host_image-}"
BAD_IMAGE="$(lifecycle_invalid_host_image)"

apply_with_host_image "${BAD_IMAGE}" || fail "apply_with_host_image should succeed when stub Apply exits 0"

grep -Fxq "TF_VAR_host_image=${BAD_IMAGE}" "${RECORD}" \
  || fail "child Apply must see injected TF_VAR_host_image"
[[ "${TF_VAR_host_image-}" == "${PARENT_BEFORE}" ]] \
  || fail "parent TF_VAR_host_image must be unchanged after apply_with_host_image"
pass "injects TF_VAR_host_image for child only"

export APPLY_STUB_RC=7
: >"${RECORD}"
if apply_with_host_image "${BAD_IMAGE}"; then
  fail "apply_with_host_image must propagate Apply non-zero exit"
fi
pass "propagates Apply exit status"

if ( apply_with_host_image "" >/dev/null 2>&1 ); then
  fail "apply_with_host_image with empty image must fail"
fi
pass "empty image fails closed"

got="$(lifecycle_invalid_host_image)"
[[ -n "${got}" ]] || fail "lifecycle_invalid_host_image must be non-empty"
[[ "${got}" != "ubuntu-26-04-x64" ]] || fail "invalid image must differ from default"
pass "lifecycle_invalid_host_image is non-empty and distinct"

echo "All apply_with_host_image checks passed."
