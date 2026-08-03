#!/usr/bin/env bash
# Parse operator OpenSSL s_client /healthcheck outcome for Tier B (#79).
# Success only when openssl exit is 0 and the captured session shows
# HTTP 200, Content-Type text/plain, body exactly "ok".

# domain_front_staging_hc_ok <openssl_exit_code> <stdout_file>
domain_front_staging_hc_ok() {
  local rc="${1-}"
  local out_file="${2-}"
  if [[ -z "${rc}" || -z "${out_file}" ]]; then
    echo "FAIL: domain_front_staging_hc_ok requires exit code and stdout file" >&2
    return 1
  fi
  if [[ "${rc}" -ne 0 ]]; then
    return 1
  fi
  [[ -f "${out_file}" ]] || return 1

  local status ctype body
  # Portable awk (macOS BSD + Linux): no IGNORECASE, no \s.
  status="$(awk '/^[Hh][Tt][Tt][Pp]\/[0-9.]+ [0-9][0-9][0-9]/ { print $2; exit }' "${out_file}")"
  [[ "${status}" == "200" ]] || return 1

  ctype="$(awk 'BEGIN{FS=":"} /^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]-[Tt][Yy][Pp][Ee]:/ {
    sub(/\r$/, "")
    print $0
    exit
  }' "${out_file}")"
  echo "${ctype}" | grep -qi 'text/plain' || return 1

  # Body is the first non-empty line after the blank line that ends headers.
  body="$(awk '
    BEGIN { hdr=1 }
    hdr && $0 ~ /^\r?$/ { hdr=0; next }
    !hdr && $0 !~ /^\r?$/ {
      sub(/\r$/, "")
      print
      exit
    }
  ' "${out_file}")"
  [[ "${body}" == "ok" ]] || return 1
  return 0
}
