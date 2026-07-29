#!/usr/bin/env bash
# Durable project-membership Adopt capability split; no cloud access.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
  {"address":"module.durables.digitalocean_volume.web","mode":"managed","values":{"id":"volume-test-id","urn":"do:volume:volume-test-id"}},
  {"address":"module.durables.digitalocean_reserved_ip.web","mode":"managed","values":{"ip_address":"203.0.113.10","urn":"do:reservedip:203.0.113.10"}},
  {"address":"module.durables.digitalocean_domain.this[\"gniewomir.pl\"]","mode":"managed","values":{"id":"gniewomir.pl","urn":"do:domain:gniewomir.pl"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:@\"]","mode":"managed","values":{"id":"1001"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:www\"]","mode":"managed","values":{"id":"1002"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:api\"]","mode":"managed","values":{"id":"1003"}},
  {"address":"module.durables.digitalocean_record.a[\"gniewomir.pl:test-acme\"]","mode":"managed","values":{"id":"1004"}}
]}]}}}
JSON
    ;;
  plan) exit 2 ;;
  apply) exit 0 ;;
esac
EOF

cat >"${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "${url}" in
  *"/v2/droplets?"*) printf '%s\n' '{"droplets":[]}' ;;
  *"/v2/projects/project-test-id/resources"*)
    printf '%s\n' '{"resources":[
      {"urn":"do:volume:volume-test-id"},
      {"urn":"do:reservedip:203.0.113.10"},
      {"urn":"do:domain:gniewomir.pl"}
    ]}'
    ;;
  *"/v2/reserved_ips/203.0.113.10")
    if [[ "${RESERVED_IP_ASSIGNED:-false}" == true ]]; then
      printf '%s\n' '{"reserved_ip":{"ip":"203.0.113.10","droplet":{"id":4242}}}'
    else
      printf '%s\n' '{"reserved_ip":{"ip":"203.0.113.10","droplet":null}}'
    fi
    ;;
  *) echo "unexpected provider request: ${url}" >&2; exit 1 ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/terraform" "${TMP_DIR}/bin/curl"

export PATH="${TMP_DIR}/bin:${PATH}"
export TERRAFORM_CALLS="${TMP_DIR}/terraform.calls"
export DIGITALOCEAN_TOKEN="test-token"
export TF_VAR_DIGITALOCEAN_PUBLIC_KEY="ssh-ed25519 test"

output="$("${REPO_ROOT}/apply.sh" --yes --env test)"
grep -Fq "Adopt: Durable Cloud Project membership will bind during Apply" <<<"${output}" \
  || fail "unassigned exact Durable membership must self-bind during Apply"
pass "Apply self-binds exact Durable membership while Reserved IP is unassigned"

: >"${TERRAFORM_CALLS}"
export RESERVED_IP_ASSIGNED=true
if "${REPO_ROOT}/apply.sh" --yes --env test >/dev/null 2>&1; then
  fail "Applied external State loss must fail closed for Durable membership"
fi
if grep -Eq '(^| )(plan |apply )' "${TERRAFORM_CALLS}"; then
  fail "Apply must not plan an unsafe Durable membership Create"
fi
pass "Apply fails closed on Applied Durable-membership State loss"
