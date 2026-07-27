#!/usr/bin/env bash
# Adopt preflight through the Apply operator-command seam; no cloud access.
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
{
  "values": {
    "root_module": {
      "child_modules": [
        {
          "address": "module.durables",
          "resources": [
            {
              "address": "module.durables.digitalocean_reserved_ip.web",
              "mode": "managed",
              "values": {"ip_address": "203.0.113.10"}
            }
          ]
        },
        {
          "address": "module.recreatables[0]",
          "resources": [
            {
              "address": "module.recreatables[0].digitalocean_droplet.web",
              "mode": "managed",
              "values": {"id": 4242}
            }
          ]
        }
      ]
    }
  }
}
JSON
    ;;
  import) exit 0 ;;
  plan) exit 2 ;;
  apply) exit 0 ;;
esac
EOF

cat >"${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CURL_CALLS}"
url="${*: -1}"
case "${url}" in
  *"/v2/projects?"*) printf '%s\n' '{"projects":[]}' ;;
  *"/v2/volumes?"*) printf '%s\n' '{"volumes":[]}' ;;
  *"/v2/domains?"*) printf '%s\n' '{"domains":[]}' ;;
  *"/v2/reserved_ips/203.0.113.10")
    printf '{"reserved_ip":{"ip":"203.0.113.10","droplet":{"id":%s}}}\n' "${PROVIDER_HOST_ID:-4242}"
    ;;
  *) echo "unexpected provider request: ${url}" >&2; exit 1 ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/terraform" "${TMP_DIR}/bin/curl"

export PATH="${TMP_DIR}/bin:${PATH}"
export TERRAFORM_CALLS="${TMP_DIR}/terraform.calls"
export CURL_CALLS="${TMP_DIR}/curl.calls"
export DIGITALOCEAN_TOKEN="test-token"
export TF_VAR_DIGITALOCEAN_PUBLIC_KEY="ssh-ed25519 test"

"${REPO_ROOT}/apply.sh" --yes --env test >/dev/null

import_call='import -input=false -var=recreatables_present=true module.recreatables[0].digitalocean_reserved_ip_assignment.web 203.0.113.10,4242'
grep -Fxq "${import_call}" "${TERRAFORM_CALLS}" \
  || fail "Apply must Adopt the exact provider assignment missing from State"

import_line="$(grep -nFx "${import_call}" "${TERRAFORM_CALLS}" | cut -d: -f1)"
plan_line="$(grep -nFx "plan -detailed-exitcode -input=false -var=recreatables_present=true" "${TERRAFORM_CALLS}" | cut -d: -f1)"
apply_line="$(grep -nFx "apply -input=false -auto-approve -var=recreatables_present=true" "${TERRAFORM_CALLS}" | cut -d: -f1)"
[[ "${import_line}" -lt "${plan_line}" && "${plan_line}" -lt "${apply_line}" ]] \
  || fail "Apply must Adopt before its Terraform plan, then apply"

pass "Apply Adopts an exact Reserved IP assignment before planning"

: >"${TERRAFORM_CALLS}"
export PROVIDER_HOST_ID=9999
if "${REPO_ROOT}/apply.sh" --yes --env test >/dev/null 2>&1; then
  fail "Apply must fail closed when the Reserved IP is assigned to a different Host"
fi
if grep -Eq '(^| )(plan |apply )' "${TERRAFORM_CALLS}"; then
  fail "Apply must not plan or apply after an Adopt endpoint conflict"
fi

pass "Apply fails closed on a wrong Reserved IP assignment endpoint"
