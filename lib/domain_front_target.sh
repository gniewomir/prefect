#!/usr/bin/env bash
# Domain-front Acceptance target FQDN selection (#77 / #79).
# Prefer lex-first want-list name whose A answers include the Reserved IP;
# else lex-first want-list name. Prints: "<fqdn> ready|not-ready" or nothing if empty.
#
# Usage:
#   domain_front_select_target <reserved_ip> [answers_file] < want-list-fqdns
# answers_file lines: "<fqdn> <ip>" (multiple IPs per FQDN allowed as separate lines).
# When answers_file is omitted, A records come from `dig +short <fqdn> A`.

domain_front_select_target() {
  local reserved_ip="${1-}"
  local answers_file="${2-}"
  if [[ -z "${reserved_ip}" ]]; then
    echo "FAIL: domain_front_select_target requires Reserved IP" >&2
    return 1
  fi

  local -a fqdns=()
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] || continue
    fqdns+=("${line}")
  done

  if [[ "${#fqdns[@]}" -eq 0 ]]; then
    return 0
  fi

  local sorted
  sorted="$(printf '%s\n' "${fqdns[@]}" | LC_ALL=C sort -u)"

  local fqdn candidate="" ready="not-ready" resolved hit
  while IFS= read -r fqdn; do
    [[ -n "${fqdn}" ]] || continue
    if [[ -z "${candidate}" ]]; then
      candidate="${fqdn}"
    fi
    hit=0
    if [[ -n "${answers_file}" ]]; then
      while IFS= read -r resolved; do
        [[ -n "${resolved}" ]] || continue
        if [[ "${resolved}" == "${reserved_ip}" ]]; then
          hit=1
          break
        fi
      done < <(awk -v f="${fqdn}" '$1 == f { print $2 }' "${answers_file}")
    else
      while IFS= read -r resolved; do
        [[ -n "${resolved}" ]] || continue
        if [[ "${resolved}" == "${reserved_ip}" ]]; then
          hit=1
          break
        fi
      done < <(dig +short "${fqdn}" A 2>/dev/null || true)
    fi
    if [[ "${hit}" -eq 1 ]]; then
      printf '%s %s\n' "${fqdn}" ready
      return 0
    fi
  done <<<"${sorted}"

  printf '%s %s\n' "${candidate}" "${ready}"
}
