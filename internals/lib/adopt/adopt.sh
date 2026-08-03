#!/usr/bin/env bash
# Adopt allowlisted provider facts into the selected Environment State (ADR-0026).
# Public interface: adopt_preflight apply|park|teardown

_ADOPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../domains/domains.sh
source "${_ADOPT_DIR}/../domains/domains.sh"

adopt_fail() {
  echo "FAIL: Adopt: $*" >&2
  return 1
}

adopt_state_values() {
  local state_json="$1"
  local address="$2"
  jq -cer --arg address "${address}" '
    [
      .. | objects
      | select(.address? == $address and .mode? == "managed")
      | .values
    ]
    | if length == 1 then .[0]
      elif length == 0 then empty
      else error("ambiguous State address: " + $address)
      end
  ' <<<"${state_json}"
}

adopt_reject_unbound_host() {
  local state_json="$1"
  local environment_slug="$2"
  local address="module.recreatables[0].digitalocean_droplet.web"
  local expected_name="propraetor-${environment_slug}-web"
  local provider_json match_count

  if adopt_state_values "${state_json}" "${address}" >/dev/null 2>&1; then
    return 0
  fi

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/droplets?per_page=200")" \
    || { adopt_fail "could not check for an unbound Host at the provider"; return 1; }
  match_count="$(jq -er --arg name "${expected_name}" \
    '[.droplets[] | select(.name == $name)] | length' <<<"${provider_json}")" \
    || { adopt_fail "invalid Host provider response"; return 1; }

  if [[ "${match_count}" -gt 0 ]]; then
    adopt_fail "Host identity '${expected_name}' exists at the provider but is absent from State; Host-by-name Adopt is forbidden"
    return 1
  fi
}

adopt_cloud_project() {
  local state_json="$1"
  local environment_slug="$2"
  local address="module.durables.digitalocean_project.propraetor"
  local expected_name="propraetor-${environment_slug}"
  local provider_json match_count project_id

  if adopt_state_values "${state_json}" "${address}" >/dev/null 2>&1; then
    return 0
  fi

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/projects?per_page=200")" \
    || { adopt_fail "could not list Cloud Projects at the provider"; return 1; }
  match_count="$(jq -er --arg name "${expected_name}" \
    '[.projects[] | select(.name == $name)] | length' <<<"${provider_json}")" \
    || { adopt_fail "invalid Cloud Project provider response"; return 1; }

  case "${match_count}" in
    0) return 0 ;;
    1) ;;
    *) adopt_fail "Cloud Project identity '${expected_name}' is ambiguous (${match_count} exact matches)"; return 1 ;;
  esac

  project_id="$(jq -er --arg name "${expected_name}" \
    '.projects[] | select(.name == $name) | .id | select(type == "string" and length > 0)' \
    <<<"${provider_json}")" \
    || { adopt_fail "Cloud Project '${expected_name}' has no provider id"; return 1; }

  echo "Adopt: Cloud Project ${expected_name} (${project_id})"
  terraform import -input=false "${address}" "${project_id}"
}

adopt_host_volume() {
  local state_json="$1"
  local environment_slug="$2"
  local address="module.durables.digitalocean_volume.web"
  local expected_name="propraetor-${environment_slug}-web-data"
  local expected_region="fra1"
  local provider_json match_count volume_id

  if adopt_state_values "${state_json}" "${address}" >/dev/null 2>&1; then
    return 0
  fi

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/volumes?name=${expected_name}&region=${expected_region}&per_page=200")" \
    || { adopt_fail "could not list Host Volumes at the provider"; return 1; }
  match_count="$(jq -er --arg name "${expected_name}" --arg region "${expected_region}" '
    [.volumes[] | select(.name == $name and .region.slug == $region)] | length
  ' <<<"${provider_json}")" \
    || { adopt_fail "invalid Host Volume provider response"; return 1; }

  case "${match_count}" in
    0) return 0 ;;
    1) ;;
    *) adopt_fail "Host Volume identity '${expected_name}' in ${expected_region} is ambiguous (${match_count} exact matches)"; return 1 ;;
  esac

  volume_id="$(jq -er --arg name "${expected_name}" --arg region "${expected_region}" '
    .volumes[]
    | select(.name == $name and .region.slug == $region)
    | .id
    | select(type == "string" and length > 0)
  ' <<<"${provider_json}")" \
    || { adopt_fail "Host Volume '${expected_name}' has no provider id"; return 1; }

  echo "Adopt: Host Volume ${expected_name} (${volume_id})"
  terraform import -input=false "${address}" "${volume_id}"
}

adopt_domain_records() {
  local state_json="$1"
  local domains_path="$2"
  local zone="$3"
  local reserved_ip="$4"
  local provider_json name address exact_count conflict_count record_id

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/domains/${zone}/records?per_page=200")" \
    || { adopt_fail "could not list records for Domain ${zone}"; return 1; }

  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    address="module.durables.digitalocean_record.a[\"${zone}:${name}\"]"
    if adopt_state_values "${state_json}" "${address}" >/dev/null 2>&1; then
      continue
    fi

    exact_count="$(jq -er --arg name "${name}" --arg ip "${reserved_ip}" '
      [.domain_records[] | select(.type == "A" and .name == $name and .data == $ip)]
      | length
    ' <<<"${provider_json}")" \
      || { adopt_fail "invalid record provider response for Domain ${zone}"; return 1; }
    conflict_count="$(jq -er --arg name "${name}" --arg ip "${reserved_ip}" '
      [
        .domain_records[]
        | select(.name == $name)
        | select((.type == "A" and .data != $ip) or .type == "CNAME")
      ]
      | length
    ' <<<"${provider_json}")" \
      || { adopt_fail "invalid record provider response for Domain ${zone}"; return 1; }

    if [[ "${conflict_count}" -gt 0 ]]; then
      adopt_fail "Domain ${zone} record '${name}' exists with a wrong endpoint or conflicting type"
      return 1
    fi
    case "${exact_count}" in
      0) continue ;;
      1) ;;
      *) adopt_fail "Domain ${zone} A record '${name}' is ambiguous (${exact_count} exact matches)"; return 1 ;;
    esac

    record_id="$(jq -er --arg name "${name}" --arg ip "${reserved_ip}" '
      .domain_records[]
      | select(.type == "A" and .name == $name and .data == $ip)
      | .id
      | select(type == "number" or type == "string")
      | tostring
    ' <<<"${provider_json}")" \
      || { adopt_fail "Domain ${zone} A record '${name}' has no provider id"; return 1; }

    echo "Adopt: Domain ${zone} A record ${name} → ${reserved_ip}"
    terraform import -input=false "${address}" "${zone},${record_id}" || return 1
  done < <(jq -r --arg zone "${zone}" '.[$zone].names[]' "${domains_path}")
}

adopt_domains() {
  local state_json="$1"
  local environment_slug="$2"
  local domains_path
  local ip_values reserved_ip=""
  local provider_json zone address match_count zone_exists
  local name record_address needs_provider=false

  domains_path="$(domains_assignment_path "${environment_slug}")" || return 1
  [[ -n "${domains_path}" ]] || return 0
  jq -e 'type == "object"' "${domains_path}" >/dev/null \
    || { adopt_fail "invalid Domain declaration ${domains_path}"; return 1; }
  [[ "$(jq -r 'keys | length' "${domains_path}")" -gt 0 ]] || return 0

  ip_values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_reserved_ip.web")" || true
  if [[ -n "${ip_values}" ]]; then
    reserved_ip="$(jq -er '.ip_address | select(type == "string" and length > 0)' <<<"${ip_values}")" \
      || { adopt_fail "Reserved IP in State has no address"; return 1; }
  fi

  while IFS= read -r zone; do
    address="module.durables.digitalocean_domain.this[\"${zone}\"]"
    if ! adopt_state_values "${state_json}" "${address}" >/dev/null 2>&1; then
      needs_provider=true
      continue
    fi
    [[ -n "${reserved_ip}" ]] || continue
    while IFS= read -r name; do
      record_address="module.durables.digitalocean_record.a[\"${zone}:${name}\"]"
      if ! adopt_state_values "${state_json}" "${record_address}" >/dev/null 2>&1; then
        needs_provider=true
        break
      fi
    done < <(jq -r --arg zone "${zone}" '.[$zone].names[]' "${domains_path}")
  done < <(jq -r 'keys[]' "${domains_path}")
  [[ "${needs_provider}" == true ]] || return 0

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/domains?per_page=200")" \
    || { adopt_fail "could not list Domains at the provider"; return 1; }

  while IFS= read -r zone; do
    [[ -n "${zone}" ]] || continue
    address="module.durables.digitalocean_domain.this[\"${zone}\"]"
    zone_exists=false
    if adopt_state_values "${state_json}" "${address}" >/dev/null 2>&1; then
      zone_exists=true
    else
      match_count="$(jq -er --arg zone "${zone}" \
        '[.domains[] | select(.name == $zone)] | length' <<<"${provider_json}")" \
        || { adopt_fail "invalid Domain provider response"; return 1; }
      case "${match_count}" in
        0) continue ;;
        1) zone_exists=true ;;
        *) adopt_fail "Domain identity '${zone}' is ambiguous (${match_count} exact matches)"; return 1 ;;
      esac

      echo "Adopt: Domain ${zone}"
      terraform import -input=false "${address}" "${zone}" || return 1
    fi

    if [[ "${zone_exists}" == true && -n "${reserved_ip}" ]]; then
      adopt_domain_records "${state_json}" "${domains_path}" "${zone}" "${reserved_ip}" || return 1
    fi
  done < <(jq -r 'keys[]' "${domains_path}")
}

adopt_reject_nondefault_project_owners() {
  local target_project_id="$1"
  local relationship="$2"
  shift 2
  local expected_urns=("$@")
  local projects_json project_id resources_json urn

  projects_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/projects?per_page=200")" \
    || { adopt_fail "could not inspect Cloud Projects for ${relationship}"; return 1; }

  while IFS= read -r project_id; do
    [[ -n "${project_id}" ]] || continue
    resources_json="$(curl -fsS \
      -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.digitalocean.com/v2/projects/${project_id}/resources?per_page=200")" \
      || { adopt_fail "could not inspect Cloud Project ${project_id} for ${relationship}"; return 1; }
    for urn in "${expected_urns[@]}"; do
      if jq -e --arg urn "${urn}" \
        '[.resources[].urn] | index($urn) != null' <<<"${resources_json}" >/dev/null; then
        adopt_fail "${relationship} endpoint ${urn} belongs to non-default Cloud Project ${project_id}, expected ${target_project_id}"
        return 1
      fi
    done
  done < <(jq -r --arg target "${target_project_id}" '
    .projects[]
    | select(.id != $target and .is_default != true)
    | .id
  ' <<<"${projects_json}")
}

adopt_project_memberships() {
  local state_json="$1"
  local environment_slug="$2"
  local lifecycle_label="$3"
  local include_host="$4"
  local durable_address="module.durables.digitalocean_project_resources.durables"
  local host_membership_address="module.recreatables[0].digitalocean_project_resources.web_host"
  local project_values project_id provider_json values urn all_present
  local domains_path
  local zone host_values host_id host_urn
  local reserved_ip_values reserved_ip reserved_ip_json assigned_host_id
  local durable_urns=()
  local durables_complete=true

  domains_path="$(domains_assignment_path "${environment_slug}")" || return 1

  if adopt_state_values "${state_json}" "${durable_address}" >/dev/null 2>&1 \
    && { [[ "${include_host}" != true ]] \
      || adopt_state_values "${state_json}" "${host_membership_address}" >/dev/null 2>&1; }; then
    return 0
  fi

  project_values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_project.propraetor")" || return 0
  project_id="$(jq -er '.id | select(type == "string" and length > 0)' <<<"${project_values}")" \
    || { adopt_fail "Cloud Project in State has no provider id"; return 1; }
  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/projects/${project_id}/resources?per_page=200")" \
    || { adopt_fail "could not inspect Cloud Project memberships for ${project_id}"; return 1; }

  if ! adopt_state_values "${state_json}" "${durable_address}" >/dev/null 2>&1; then
    values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_volume.web")" || {
      values=""
      durables_complete=false
    }
    [[ -n "${values}" ]] && durable_urns+=("$(jq -er '.urn' <<<"${values}")")
    values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_reserved_ip.web")" || {
      values=""
      durables_complete=false
    }
    [[ -n "${values}" ]] && durable_urns+=("$(jq -er '.urn' <<<"${values}")")
    if [[ -n "${domains_path}" ]]; then
      while IFS= read -r zone; do
        values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_domain.this[\"${zone}\"]")" || {
          durables_complete=false
          break
        }
        durable_urns+=("$(jq -er '.urn' <<<"${values}")")
      done < <(jq -r 'keys[]' "${domains_path}")
    fi

    if [[ "${durables_complete}" == true && ${#durable_urns[@]} -gt 0 ]]; then
      all_present=true
      for urn in "${durable_urns[@]}"; do
        if ! jq -e --arg urn "${urn}" \
          '[.resources[].urn] | index($urn) != null' <<<"${provider_json}" >/dev/null; then
          all_present=false
        fi
      done
      if [[ "${all_present}" == true ]]; then
        reserved_ip_values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_reserved_ip.web")" \
          || { adopt_fail "Durable membership has no Reserved IP endpoint in State"; return 1; }
        reserved_ip="$(jq -er '.ip_address | select(type == "string" and length > 0)' <<<"${reserved_ip_values}")" \
          || { adopt_fail "Reserved IP in State has no address"; return 1; }
        reserved_ip_json="$(curl -fsS \
          -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
          -H "Content-Type: application/json" \
          "https://api.digitalocean.com/v2/reserved_ips/${reserved_ip}")" \
          || { adopt_fail "could not inspect Reserved IP ${reserved_ip} before Durable membership binding"; return 1; }
        assigned_host_id="$(jq -er '.reserved_ip.droplet.id // empty | tostring' <<<"${reserved_ip_json}")" || true
        if [[ -n "${assigned_host_id}" ]]; then
          adopt_fail "Durable Cloud Project membership is exact but missing from State after Host ${assigned_host_id} attachment; this external State-loss incident is tracked in #67"
          return 1
        fi
        echo "Adopt: Durable Cloud Project membership will bind during ${lifecycle_label}"
      else
        adopt_reject_nondefault_project_owners \
          "${project_id}" "Durable Cloud Project membership" "${durable_urns[@]}" || return 1
      fi
    fi
  fi

  [[ "${include_host}" == true ]] || return 0
  if adopt_state_values "${state_json}" "${host_membership_address}" >/dev/null 2>&1; then
    return 0
  fi
  host_values="$(adopt_state_values "${state_json}" "module.recreatables[0].digitalocean_droplet.web")" || return 0
  host_id="$(jq -er '.id | select(type == "number" or type == "string") | tostring' <<<"${host_values}")" \
    || { adopt_fail "Host in State has no provider id"; return 1; }
  host_urn="do:droplet:${host_id}"
  if jq -e --arg urn "${host_urn}" \
    '[.resources[].urn] | index($urn) != null' <<<"${provider_json}" >/dev/null; then
    echo "Adopt: Host Cloud Project membership will bind during ${lifecycle_label}"
  else
    adopt_reject_nondefault_project_owners \
      "${project_id}" "Host Cloud Project membership" "${host_urn}" || return 1
  fi
}

adopt_volume_attachment() {
  local state_json="$1"
  local attachment_address="module.recreatables[0].digitalocean_volume_attachment.web"
  local volume_values host_values volume_id host_id provider_json
  local attached_ids

  if adopt_state_values "${state_json}" "${attachment_address}" >/dev/null 2>&1; then
    return 0
  fi
  volume_values="$(adopt_state_values "${state_json}" "module.durables.digitalocean_volume.web")" || return 0
  host_values="$(adopt_state_values "${state_json}" "module.recreatables[0].digitalocean_droplet.web")" || return 0
  volume_id="$(jq -er '.id | select(type == "string" and length > 0)' <<<"${volume_values}")" \
    || { adopt_fail "Host Volume in State has no provider id"; return 1; }
  host_id="$(jq -er '.id | select(type == "number" or type == "string") | tostring' <<<"${host_values}")" \
    || { adopt_fail "Host in State has no provider id"; return 1; }

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/volumes/${volume_id}")" \
    || { adopt_fail "could not inspect Host Volume ${volume_id} attachment"; return 1; }
  attached_ids="$(jq -cer '[.volume.droplet_ids[] | tostring]' <<<"${provider_json}")" \
    || { adopt_fail "invalid Host Volume provider response for ${volume_id}"; return 1; }

  if jq -e --arg host_id "${host_id}" \
    'length == 1 and .[0] == $host_id' <<<"${attached_ids}" >/dev/null; then
    echo "Adopt: Host Volume attachment will bind during Apply"
    return 0
  fi
  if jq -e 'length == 0' <<<"${attached_ids}" >/dev/null; then
    return 0
  fi

  adopt_fail "Host Volume ${volume_id} is attached to a wrong Host; expected ${host_id}, found ${attached_ids}"
}

adopt_reserved_ip_assignment() {
  local state_json="$1"
  local assignment_address="module.recreatables[0].digitalocean_reserved_ip_assignment.web"
  local ip_address="module.durables.digitalocean_reserved_ip.web"
  local host_address="module.recreatables[0].digitalocean_droplet.web"
  local ip_values host_values ip host_id provider_json provider_host_id

  if adopt_state_values "${state_json}" "${assignment_address}" >/dev/null 2>&1; then
    return 0
  fi

  ip_values="$(adopt_state_values "${state_json}" "${ip_address}")" || return 0
  host_values="$(adopt_state_values "${state_json}" "${host_address}")" || return 0
  ip="$(jq -er '.ip_address | select(type == "string" and length > 0)' <<<"${ip_values}")" \
    || { adopt_fail "Reserved IP in State has no address"; return 1; }
  host_id="$(jq -er '.id | select(type == "number" or type == "string") | tostring' <<<"${host_values}")" \
    || { adopt_fail "Host in State has no provider id"; return 1; }

  provider_json="$(curl -fsS \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.digitalocean.com/v2/reserved_ips/${ip}")" \
    || { adopt_fail "could not inspect Reserved IP ${ip} at the provider"; return 1; }

  provider_host_id="$(jq -er '.reserved_ip.droplet.id // empty | tostring' <<<"${provider_json}")" || true
  if [[ -z "${provider_host_id}" ]]; then
    return 0
  fi
  if [[ "${provider_host_id}" != "${host_id}" ]]; then
    adopt_fail "Reserved IP ${ip} is assigned to Host ${provider_host_id}, expected State Host ${host_id}"
    return 1
  fi

  echo "Adopt: Reserved IP ${ip} assignment to Host ${host_id}"
  terraform import -input=false -var=recreatables_present=true \
    "${assignment_address}" "${ip},${host_id}"
}

adopt_preflight() {
  local lifecycle="${1-}"
  local environment_raw="${2-}"
  local environment_slug state_json

  case "${lifecycle}" in
    apply | park | teardown) ;;
    *) adopt_fail "unknown lifecycle '${lifecycle}'"; return 1 ;;
  esac

  command -v jq >/dev/null || { adopt_fail "jq not found"; return 1; }
  command -v curl >/dev/null || { adopt_fail "curl not found"; return 1; }

  environment_slug="$(environment_slug_for "${environment_raw}")" \
    || { adopt_fail "could not resolve Environment identity"; return 1; }
  state_json="$(terraform show -json)" \
    || { adopt_fail "could not inspect selected Environment State"; return 1; }

  adopt_reject_unbound_host "${state_json}" "${environment_slug}" || return 1
  adopt_cloud_project "${state_json}" "${environment_slug}" || return 1
  adopt_host_volume "${state_json}" "${environment_slug}" || return 1
  adopt_domains "${state_json}" "${environment_slug}" || return 1

  if [[ "${lifecycle}" == "apply" ]]; then
    adopt_project_memberships "${state_json}" "${environment_slug}" "Apply" true || return 1
    adopt_volume_attachment "${state_json}" || return 1
    adopt_reserved_ip_assignment "${state_json}"
  elif [[ "${lifecycle}" == "park" ]]; then
    adopt_project_memberships "${state_json}" "${environment_slug}" "Park" false
  fi
}
