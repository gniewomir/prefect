#!/usr/bin/env bash
# Seam: apply_with_public_key — TF_VAR_DIGITALOCEAN_PUBLIC_KEY for one Apply only (#64).
# No cloud access; stub apply.sh records the env seen by the child.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export REPO_ROOT="${TMP_DIR}/repo"
export PREFECT_ENV=test
export DIGITALOCEAN_TOKEN=test-token
export TF_VAR_DIGITALOCEAN_PUBLIC_KEY="ssh-ed25519 PARENTKEY parent@test"

mkdir -p "${REPO_ROOT}/lib" "${REPO_ROOT}/test" \
  "${REPO_ROOT}/config/environments/test"
cp "${REAL_ROOT}/lib/environment.sh" "${REPO_ROOT}/lib/environment.sh"
cat >"${REPO_ROOT}/test/lib.sh" <<'EOF'
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
configured_domain_names() { :; }
environment_domains_path() { :; }
EOF

RECORD="${TMP_DIR}/apply.record"
cat >"${REPO_ROOT}/apply.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'TF_VAR_DIGITALOCEAN_PUBLIC_KEY=%s\n' "\${TF_VAR_DIGITALOCEAN_PUBLIC_KEY-}"
  printf 'args=%s\n' "\$*"
} >"${RECORD}"
exit "\${APPLY_EXIT:-0}"
EOF
chmod +x "${REPO_ROOT}/apply.sh"

# shellcheck source=lib.sh
source "${REAL_ROOT}/lifecycle-test/lib.sh"

PARENT_BEFORE="${TF_VAR_DIGITALOCEAN_PUBLIC_KEY}"
BAD_KEY="$(lifecycle_invalid_public_key)"

apply_with_public_key "${BAD_KEY}" || fail "apply_with_public_key should succeed when stub Apply exits 0"

grep -Fxq "TF_VAR_DIGITALOCEAN_PUBLIC_KEY=${BAD_KEY}" "${RECORD}" \
  || fail "child Apply must see the overridden public key"
grep -Fxq "args=--yes --env test" "${RECORD}" \
  || fail "child Apply must receive --yes --env \${PREFECT_ENV}"

[[ "${TF_VAR_DIGITALOCEAN_PUBLIC_KEY}" == "${PARENT_BEFORE}" ]] \
  || fail "parent TF_VAR_DIGITALOCEAN_PUBLIC_KEY must be unchanged after apply_with_public_key"
pass "overrides public key for child Apply only; parent env restored"

export APPLY_EXIT=1
if apply_with_public_key "${BAD_KEY}"; then
  fail "apply_with_public_key must propagate Apply non-zero exit"
fi
unset APPLY_EXIT
pass "propagates Apply failure"

if ( apply_with_public_key "" >/dev/null 2>&1 ); then
  fail "apply_with_public_key with empty key must fail"
fi
pass "rejects empty public key"

got="$(lifecycle_invalid_public_key)"
[[ -n "${got}" ]] || fail "lifecycle_invalid_public_key must be non-empty"
[[ "${got}" != "${PARENT_BEFORE}" ]] || fail "invalid key must differ from a real key"
pass "lifecycle_invalid_public_key is non-empty and distinct"

echo "All apply_with_public_key checks passed."
