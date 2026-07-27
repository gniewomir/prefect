#!/usr/bin/env bash
# Stack lifecycle operator-command seam. Uses a recording Terraform adapter; no cloud access.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TERRAFORM_CALLS}"
case "${1-}" in
  workspace) exit 0 ;;
  plan) exit 2 ;;
  apply) exit 0 ;;
  state)
    printf '%s\n' "digitalocean_droplet.web"
    exit 0
    ;;
  destroy) exit 0 ;;
esac
exit 0
EOF
chmod +x "${TMP_DIR}/bin/terraform"

export PATH="${TMP_DIR}/bin:${PATH}"
export TERRAFORM_CALLS="${TMP_DIR}/terraform.calls"
export DIGITALOCEAN_TOKEN="test-token"
export TF_VAR_DIGITALOCEAN_PUBLIC_KEY="ssh-ed25519 test"

printf 'park\n' | "${REPO_ROOT}/park.sh" --env test >/dev/null

grep -Fxq \
  "plan -detailed-exitcode -input=false -var=recreatables_present=false" \
  "${TERRAFORM_CALLS}" \
  || fail "Park must plan complete Recreatable absence"
grep -Fxq \
  "apply -input=false -auto-approve -var=recreatables_present=false" \
  "${TERRAFORM_CALLS}" \
  || fail "Park must apply complete Recreatable absence"

if grep -Eq -- '(^| )(-target=|state |destroy($| ))' "${TERRAFORM_CALLS}"; then
  fail "Park must not use targets, State inspection, or terraform destroy"
fi

pass "Park supplies non-sticky Recreatable absence to a complete Terraform plan"
