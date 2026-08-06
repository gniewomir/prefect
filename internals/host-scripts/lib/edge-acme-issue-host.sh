#!/usr/bin/env bash
# Host ACME issue helpers: detect installed PEM vs configured CA directory (ADR-0045).
# Sourced by acme-run. Expects: CERTS_DIR, ACME_DIR. Reads EDGE_ACME_DIRECTORY (default staging).

# Return 0 when Host fullchain for host is a Let's Encrypt cert from the wrong
# directory relative to EDGE_ACME_DIRECTORY (staging↔production cutover).
# Missing PEM, unreadable PEM, and non-LE placeholders → 1 (not a wrong-CA case).
acme_installed_pem_wrong_ca() {
  local host="${1-}"
  local pem="${CERTS_DIR}/${host}/fullchain.pem"
  [[ -n "${host}" && -f "${pem}" ]] || return 1
  local issuer
  issuer="$(openssl x509 -noout -issuer -in "${pem}" 2>/dev/null || true)"
  [[ -n "${issuer}" ]] || return 1
  # Only LE chains participate in staging↔production cutover detection.
  [[ "${issuer}" == *"Let's Encrypt"* ]] || return 1
  case "${EDGE_ACME_DIRECTORY:-staging}" in
    production | prod)
      [[ "${issuer}" == *"(STAGING)"* ]] && return 0
      return 1
      ;;
    staging | *)
      [[ "${issuer}" == *"(STAGING)"* ]] && return 1
      return 0
      ;;
  esac
}

# Remove lego on-disk material for one FQDN so the next `lego run` issues fresh
# against the configured CA (staging↔production cutover). Do not touch Host PEMs;
# install_pems_from_lego replaces them only after a successful issue.
acme_clear_lego_certificate() {
  local host="${1-}"
  local dir="${ACME_DIR:-}/certificates"
  [[ -n "${host}" && -n "${ACME_DIR:-}" ]] || return 1
  [[ -d "${dir}" ]] || return 0
  rm -f \
    "${dir}/${host}.crt" \
    "${dir}/${host}.issuer.crt" \
    "${dir}/${host}.key" \
    "${dir}/${host}.json" \
    "${dir}/${host}.pfx"
}
