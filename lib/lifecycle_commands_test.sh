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
  show)
    cat <<'JSON'
{"values":{"root_module":{"child_modules":[{"address":"module.durables","resources":[
  {"address":"module.durables.digitalocean_project.prefect","mode":"managed","values":{"id":"project-test-id"}},
  {"address":"module.durables.digitalocean_volume.web","mode":"managed","values":{"id":"volume-test-id"}},
  {"address":"module.durables.digitalocean_reserved_ip.web","mode":"managed","values":{"ip_address":"203.0.113.10"}},
  {"address":"module.durables.digitalocean_domain.this[\"gniewomir.pl\"]","mode":"managed","values":{"id":"gniewomir.pl"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:@\"]","mode":"managed","values":{"id":"1001"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:www\"]","mode":"managed","values":{"id":"1002"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:api\"]","mode":"managed","values":{"id":"1003"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:test-acme\"]","mode":"managed","values":{"id":"1004"}},
  {"address":"module.durables.digitalocean_project_resources.durables","mode":"managed","values":{"id":"project-test-id"}}
]},{"address":"module.recreatables[0]","resources":[
  {"address":"module.recreatables[0].digitalocean_droplet.web","mode":"managed","values":{"id":4242}},
  {"address":"module.recreatables[0].digitalocean_reserved_ip_assignment.web","mode":"managed","values":{"ip_address":"203.0.113.10","droplet_id":4242}},
  {"address":"module.recreatables[0].digitalocean_project_resources.web_host","mode":"managed","values":{"id":"project-test-id"}},
  {"address":"module.recreatables[0].digitalocean_volume_attachment.web","mode":"managed","values":{"id":"attachment-test-id"}}
]}]}}}
JSON
    ;;
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
  fail "Park must not use targets, raw terraform state commands, or terraform destroy"
fi

pass "Park supplies non-sticky Recreatable absence to a complete Terraform plan"

: >"${TERRAFORM_CALLS}"
TF_VAR_recreatables_present=false "${REPO_ROOT}/apply.sh" --yes --env test >/dev/null

grep -Fxq \
  "apply -input=false -auto-approve -var=recreatables_present=true" \
  "${TERRAFORM_CALLS}" \
  || fail "Apply must explicitly request Recreatable presence"

pass "Apply overrides ambient variables with Recreatable presence"

: >"${TERRAFORM_CALLS}"
TF_VAR_recreatables_present=false "${REPO_ROOT}/apply.sh" --env test >/dev/null

grep -Fxq \
  "apply -var=recreatables_present=true" \
  "${TERRAFORM_CALLS}" \
  || fail "interactive Apply must explicitly request Recreatable presence"

pass "interactive Apply requests Recreatable presence"
