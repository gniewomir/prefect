# Shared helpers for Lifecycle Tests. Sourced by case scripts (not executed by the runner).
# Requires fixture env from internals/lifecycle-tests.sh: REPO_ROOT. Optional: VERIFY_SSH_IDENTITY.
# Reuses Acceptance Test helpers for pass/fail / SSH / ihp-done.
# Resolve siblings via REPO_ROOT — not BASH_SOURCE — so sourcing from zsh (operator
# shells) works the same as bash (Lifecycle cases run under bash).

[[ -n "${REPO_ROOT:-}" ]] || {
  echo "FAIL: fixture missing REPO_ROOT (run via ./internals/lifecycle-tests.sh)" >&2
  # return when sourced; exit when executed as a script
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
}

# shellcheck source=../acceptance-tests/lib.sh
source "${REPO_ROOT}/internals/acceptance-tests/lib.sh"
# shellcheck source=lib/environment.sh
source "${REPO_ROOT}/internals/lib/environment.sh"

STACK_DIR="${REPO_ROOT}/internals/terraform"

# Provider-visible Durable identifiers (not State addresses). Derived from PLATFORM_ENV.
DURABLE_VOLUME_NAME="$(environment_volume_name_for "${PLATFORM_ENV:-test}")"
DURABLE_VOLUME_REGION="fra1"
HOST_NAME="prefect-${PLATFORM_ENV:-test}-web"

# Assert Reserved IP still exists at the provider (survives Park).
assert_reserved_ip_present() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_reserved_ip_present: empty IP"
  local body
  body="$(do_api_get "/v2/reserved_ips/${ip}")" \
    || fail "Reserved IP ${ip} not found at provider"
  echo "${body}" | jq -e --arg ip "${ip}" '.reserved_ip.ip == $ip' >/dev/null \
    || fail "Reserved IP provider payload mismatch for ${ip}"
  pass "Reserved IP ${ip} present at provider"
}

# Provider Cloud Project id for the selected Environment.
stack_cloud_project_id() {
  provider_cloud_project_id
}

# Provider Host Volume id for the selected Environment (empty when absent).
stack_host_volume_id() {
  provider_host_volume_json | jq -r '.id // empty'
}

# Provider Host JSON for the Environment Host name (empty when absent).
provider_host_by_name_json() {
  local name="${1:-${HOST_NAME}}"
  do_api_get "/v2/droplets?name=${name}&per_page=200" \
    | jq -c --arg name "${name}" '[.droplets[] | select(.name == $name)] | .[0] // empty'
}

# Assert every configured Durable is a Cloud Project member at the provider.
assert_durables_in_cloud_project() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_durables_in_cloud_project: empty IP"
  local project_id body expected_urn
  project_id="$(stack_cloud_project_id)"
  [[ -n "${project_id}" ]] || fail "Cloud Project prefect not found at provider"
  body="$(do_api_get "/v2/projects/${project_id}/resources")" \
    || fail "Cloud Project resources list failed for ${project_id}"
  while IFS= read -r expected_urn; do
    [[ -n "${expected_urn}" ]] || continue
    echo "${body}" | jq -e --arg urn "${expected_urn}" \
      '[.resources[].urn] | index($urn) != null' >/dev/null \
      || fail "Durable ${expected_urn} not in Cloud Project Prefect (${project_id})"
  done < <(
    # Durable Reserved IP membership uses do:reservedip:<ip> (provider list shape).
    printf 'do:reservedip:%s\n' "${ip}"
    volume_id="$(provider_host_volume_json | jq -r '.id // empty')"
    [[ -n "${volume_id}" ]] && printf 'do:volume:%s\n' "${volume_id}"
    while IFS= read -r zone; do
      [[ -n "${zone}" ]] && printf 'do:domain:%s\n' "${zone}"
    done < <(stack_domain_names)
  )
  pass "all Durables remain in Cloud Project Prefect"
}

# Assert Host Volume still exists at the provider (survives Park).
assert_volume_present() {
  local name="${1:-${DURABLE_VOLUME_NAME}}"
  local region="${2:-${DURABLE_VOLUME_REGION}}"
  local body
  body="$(do_api_get "/v2/volumes?name=${name}&region=${region}")" \
    || fail "volume list request failed for ${name}"
  echo "${body}" | jq -e '.volumes | length >= 1' >/dev/null \
    || fail "Host Volume ${name} not found at provider in ${region}"
  pass "Host Volume ${name} present at provider"
}

# Assert Reserved IP is gone at the provider (after Teardown).
assert_reserved_ip_absent() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_reserved_ip_absent: empty IP"
  require_do_token
  local http_code
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/reserved_ips/${ip}")" \
    || fail "Reserved IP lookup request failed for ${ip}"
  [[ "${http_code}" == "404" ]] \
    || fail "Reserved IP ${ip} still present at provider (HTTP ${http_code})"
  pass "Reserved IP ${ip} gone from provider"
}

assert_cloud_project_absent() {
  local project_id="$1"
  [[ -n "${project_id}" ]] || fail "assert_cloud_project_absent: empty project id"
  require_do_token
  local http_code
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/projects/${project_id}")" \
    || fail "Cloud Project lookup failed for ${project_id}"
  [[ "${http_code}" == "404" ]] \
    || fail "Cloud Project ${project_id} still present at provider (HTTP ${http_code})"
  pass "Cloud Project gone from provider"
}

# Assert Host Volume is gone at the provider (after Teardown).
assert_volume_absent() {
  local name="${1:-${DURABLE_VOLUME_NAME}}"
  local region="${2:-${DURABLE_VOLUME_REGION}}"
  local body
  body="$(do_api_get "/v2/volumes?name=${name}&region=${region}")" \
    || fail "volume list request failed for ${name}"
  echo "${body}" | jq -e '.volumes | length == 0' >/dev/null \
    || fail "Host Volume ${name} still present at provider in ${region}"
  pass "Host Volume ${name} gone from provider"
}

# Configured Domain apexes for the selected Environment.
stack_domain_names() {
  configured_domain_names
}

# Assert each Stack Domain zone still exists and has A → Reserved IP (survives Park).
# No-op pass when zero Domains are configured.
assert_domains_present() {
  local ip="$1"
  [[ -n "${ip}" ]] || fail "assert_domains_present: empty Reserved IP"
  local zones zone body
  zones="$(stack_domain_names)"
  if [[ -z "${zones}" ]]; then
    pass "Domain Durables not configured — skip Domain present asserts"
    return 0
  fi
  while IFS= read -r zone; do
    [[ -z "${zone}" ]] && continue
    do_api_get "/v2/domains/${zone}" >/dev/null \
      || fail "Domain ${zone} not found at provider"
    body="$(do_api_get "/v2/domains/${zone}/records")" \
      || fail "Domain ${zone} records list failed"
    echo "${body}" | jq -e --arg ip "${ip}" \
      '[.domain_records[] | select(.type == "A" and .data == $ip)] | length >= 1' >/dev/null \
      || fail "Domain ${zone} has no A record → Reserved IP ${ip} at provider"
    pass "Domain ${zone} present with A → ${ip}"
  done <<< "${zones}"
}

# Assert each listed Domain zone is gone at the provider (after Teardown).
assert_domains_absent() {
  local zones="$1"
  if [[ -z "${zones}" ]]; then
    pass "Domain Durables were not configured — skip Domain absent asserts"
    return 0
  fi
  require_do_token
  local zone http_code
  while IFS= read -r zone; do
    [[ -z "${zone}" ]] && continue
    http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.digitalocean.com/v2/domains/${zone}")" \
      || fail "Domain lookup request failed for ${zone}"
    [[ "${http_code}" == "404" ]] \
      || fail "Domain ${zone} still present at provider (HTTP ${http_code})"
    pass "Domain ${zone} gone from provider"
  done <<< "${zones}"
}

# Assert Stack State has no managed addresses (Teardown leftover: empty).
assert_stack_empty() {
  local addrs
  addrs="$(cd "${STACK_DIR}" && terraform state list)"
  [[ -z "${addrs}" ]] || fail "Stack State not empty after Teardown: ${addrs}"
  pass "Stack State empty"
}

stack_reserved_ip() {
  (cd "${STACK_DIR}" && terraform output -raw reserved_ip)
}

# Assert the Environment Host exists at the provider (Applied Recreatable).
assert_host_present() {
  local host_json
  host_json="$(provider_host_by_name_json)"
  [[ -n "${host_json}" && "${host_json}" != "null" ]] \
    || fail "Host ${HOST_NAME} not found at provider"
  pass "Host ${HOST_NAME} present at provider"
}

# Assert the Environment Host is absent at the provider (Parked Recreatable).
assert_host_absent() {
  local host_json
  host_json="$(provider_host_by_name_json)"
  [[ -z "${host_json}" || "${host_json}" == "null" ]] \
    || fail "Host ${HOST_NAME} still present at provider after Park"
  pass "Host ${HOST_NAME} absent at provider"
}

# Assert Host Cloud Project membership matches Applied (present) or Parked (absent).
assert_host_membership() {
  local expect="$1" # present | absent
  local project_id body host_json host_id host_urn
  project_id="$(stack_cloud_project_id)"
  [[ -n "${project_id}" ]] || fail "Cloud Project not found at provider"
  body="$(do_api_get "/v2/projects/${project_id}/resources?per_page=200")" \
    || fail "Cloud Project resources list failed for ${project_id}"

  case "${expect}" in
    present)
      host_json="$(provider_host_by_name_json)"
      [[ -n "${host_json}" && "${host_json}" != "null" ]] \
        || fail "Host ${HOST_NAME} not found at provider for membership assert"
      host_id="$(echo "${host_json}" | jq -r '.id | tostring')"
      host_urn="do:droplet:${host_id}"
      echo "${body}" | jq -e --arg urn "${host_urn}" \
        '[.resources[].urn] | index($urn) != null' >/dev/null \
        || fail "Host ${host_urn} not in Cloud Project (Applied membership required)"
      pass "Host membership present in Cloud Project (${host_urn})"
      ;;
    absent)
      # This Stack owns one Host per Environment; Parked means no droplet URNs.
      if echo "${body}" | jq -e \
        '[.resources[].urn] | map(select(startswith("do:droplet:"))) | length == 0' >/dev/null; then
        pass "Host membership absent from Cloud Project"
        return 0
      fi
      fail "Cloud Project still lists a droplet URN while Host membership should be absent"
      ;;
    *)
      fail "assert_host_membership: expect present|absent, got '${expect}'"
      ;;
  esac
}

# Assert Reserved IP remains a Durable Cloud Project member (Park and Apply).
assert_reserved_ip_membership() {
  local ip="$1"
  local project_id body
  [[ -n "${ip}" ]] || fail "assert_reserved_ip_membership: empty IP"
  project_id="$(stack_cloud_project_id)"
  [[ -n "${project_id}" ]] || fail "Cloud Project not found at provider"
  body="$(do_api_get "/v2/projects/${project_id}/resources?per_page=200")" \
    || fail "Cloud Project resources list failed for ${project_id}"
  echo "${body}" | jq -e --arg urn "do:reservedip:${ip}" \
    '[.resources[].urn] | index($urn) != null' >/dev/null \
    || fail "Reserved IP do:reservedip:${ip} not in Cloud Project"
  pass "Reserved IP membership present in Cloud Project (Durable)"
}

# Run Apply and require the operator-visible empty presence plan (Already Applied).
assert_apply_noop() {
  local out
  out="$("${REPO_ROOT}/apply.sh" --yes --env "${PLATFORM_ENV}" 2>&1)" || {
    echo "${out}" >&2
    fail "Apply failed while expecting an empty presence plan"
  }
  echo "${out}" | grep -Fq "Already Applied" \
    || fail "repeating Apply did not report Already Applied (empty presence plan)"
  pass "repeating Apply is a no-op (empty presence plan)"
}

# Run Park and require the operator-visible empty absence plan (Already Parked).
assert_park_noop() {
  local out
  out="$(printf 'park\n' | "${REPO_ROOT}/park.sh" --env "${PLATFORM_ENV}" 2>&1)" || {
    echo "${out}" >&2
    fail "Park failed while expecting an empty absence plan"
  }
  echo "${out}" | grep -Fq "Already Parked" \
    || fail "repeating Park did not report Already Parked (empty absence plan)"
  pass "repeating Park is a no-op (empty absence plan)"
}

# Write a file on the mounted Host Volume and flush it before Park can detach.
# Park destroys the Host / volume attachment without a guest unmount; dirty page
# cache is not durable across that detach (Lifecycle marker would read back from
# cache then vanish after Apply).
write_host_volume_file() {
  local path="$1"
  local body="$2"
  require_ip
  acceptance_host_session
  host_ssh bash -s <<EOF
set -euo pipefail
findmnt --mountpoint /var/lib/host-volume >/dev/null \
  || { echo "FAIL: /var/lib/host-volume not mounted" >&2; exit 1; }
printf '%s\n' '${body}' > '${path}'
# Flush file data + metadata; then a global sync as belt-and-braces before Park.
sync '${path}'
sync
got="\$(cat '${path}')"
[[ "\${got}" == '${body}' ]] || {
  echo "FAIL: Host Volume write/read mismatch (got: '\${got}')" >&2
  exit 1
}
EOF
}

# Poll until pubkey SSH to root@$IP works (Host create / boot lag after Apply).
# Optional: SSH_READY_TIMEOUT_SECONDS (default 300).
wait_until_ssh_reachable() {
  require_ip
  acceptance_host_session
  local timeout="${SSH_READY_TIMEOUT_SECONDS:-300}"
  local deadline=$((SECONDS + timeout))
  echo "Waiting for SSH at ${IP} (up to ${timeout}s) ..."
  while ((SECONDS < deadline)); do
    if host_ssh "true" >/dev/null 2>&1; then
      pass "SSH reachable at ${IP}"
      return 0
    fi
    sleep 5
  done
  fail "SSH not reachable at ${IP} within ${timeout}s"
}

# Poll until Host Volume is mounted at /var/lib/host-volume (does not wait for full IHP).
# Optional: VOLUME_MOUNT_TIMEOUT_SECONDS (default 300).
wait_until_volume_mounted() {
  require_ip
  acceptance_host_session
  local timeout="${VOLUME_MOUNT_TIMEOUT_SECONDS:-300}"
  local deadline=$((SECONDS + timeout))
  echo "Waiting for Host Volume mount at ${IP}:/var/lib/host-volume (up to ${timeout}s) ..."
  while ((SECONDS < deadline)); do
    if host_ssh "findmnt --mountpoint /var/lib/host-volume" >/dev/null 2>&1; then
      pass "Host Volume mounted at /var/lib/host-volume"
      return 0
    fi
    sleep 5
  done
  fail "Host Volume not mounted at /var/lib/host-volume within ${timeout}s"
}

# Absolute path to committed domains.json (never the override).
domains_committed_path() {
  printf '%s/config/environments/%s/domains.json\n' "${REPO_ROOT}" "${PLATFORM_ENV}"
}

# Absolute path to domains.override.json for the selected Environment.
domains_override_path() {
  printf '%s/config/environments/%s/domains.override.json\n' "${REPO_ROOT}" "${PLATFORM_ENV}"
}

# Remove internal Domain override if present.
remove_domain_override() {
  rm -f "$(domains_override_path)"
}

# Write domains.override.json = committed map + lifecycle-test.<lex-first-apex> {"names":["@"]}.
# Prints the fixture apex on stdout. Fails if committed Domains are missing or empty.
write_additive_domain_override() {
  local committed override base fixture
  committed="$(domains_committed_path)"
  override="$(domains_override_path)"
  [[ -f "${committed}" ]] || fail "committed Domain assignment missing: ${committed}"
  base="$(jq -er 'keys | sort | .[0] // empty' "${committed}")" \
    || fail "could not read committed Domain apexes from ${committed}"
  [[ -n "${base}" ]] || fail "committed Domains empty — need a base apex for additive fixture"
  fixture="lifecycle-test.${base}"
  jq -e --arg fixture "${fixture}" '
    . + {($fixture): {"names": ["@"]}}
  ' "${committed}" >"${override}" \
    || fail "could not write Domain override ${override}"
  printf '%s\n' "${fixture}"
}

# Write domains.override.json = committed map minus the lex-first apex (subtractive Durable).
# Prints the dropped apex on stdout. Fails if committed Domains are missing or empty.
write_subtractive_domain_override() {
  local committed override dropped
  committed="$(domains_committed_path)"
  override="$(domains_override_path)"
  [[ -f "${committed}" ]] || fail "committed Domain assignment missing: ${committed}"
  dropped="$(jq -er 'keys | sort | .[0] // empty' "${committed}")" \
    || fail "could not read committed Domain apexes from ${committed}"
  [[ -n "${dropped}" ]] || fail "committed Domains empty — need an apex to drop for subtractive fixture"
  jq -e --arg dropped "${dropped}" 'del(.[$dropped])' "${committed}" >"${override}" \
    || fail "could not write Domain override ${override}"
  printf '%s\n' "${dropped}"
}

# Known-invalid SSH public key for Recreatable fault injection (#64).
# Non-empty so ./apply.sh does not fail closed before planning; provider rejects at
# digitalocean_ssh_key create (after Durables converge).
lifecycle_invalid_public_key() {
  printf '%s\n' 'not-a-valid-ssh-public-key'
}

# Run ./apply.sh --yes --env $PLATFORM_ENV with TF_VAR_DIGITALOCEAN_PUBLIC_KEY set only
# for that child process (parent env unchanged). Propagates Apply's exit status.
apply_with_public_key() {
  local public_key="${1-}"
  [[ -n "${public_key}" ]] || fail "apply_with_public_key: empty public key"
  TF_VAR_DIGITALOCEAN_PUBLIC_KEY="${public_key}" \
    "${REPO_ROOT}/apply.sh" --yes --env "${PLATFORM_ENV}"
}

