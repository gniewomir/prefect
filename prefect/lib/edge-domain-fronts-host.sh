#!/usr/bin/env bash
# Edge Domain fronts + placeholder PEM helpers (sourced by Edge Component Setup).
# Expects: CERTS_DIR, WANT_LIST; for Domain fronts also DOMAINS_DIR, ROUTES_DIR.
# Optional: USER_NAME for ownership after writes.
#
# ADR-0028 / ADR-0029 / #78.

# Print non-comment want-list FQDNs, one per line.
_edge_want_list_fqdns() {
  local fqdn
  [[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"
  while IFS= read -r fqdn || [[ -n "${fqdn}" ]]; do
    [[ "${fqdn}" =~ ^[[:space:]]*(#|$) ]] && continue
    printf '%s\n' "${fqdn}"
  done <"${WANT_LIST}"
}

# Create-if-missing self-signed PEMs for each want-list FQDN (ADR-0029).
# Both fullchain.pem + privkey.pem present → never touch.
# Either missing → write a fresh pair (CN+SAN = FQDN).
# Names leaving the want-list are not pruned.
edge_plant_placeholder_pems() {
  local fqdn dest full key tmpcnf
  local -a names=()

  mkdir -p "${CERTS_DIR}"
  while IFS= read -r fqdn || [[ -n "${fqdn}" ]]; do
    [[ -n "${fqdn}" ]] || continue
    names+=("${fqdn}")
  done < <(_edge_want_list_fqdns)

  for fqdn in "${names[@]+"${names[@]}"}"; do
    dest="${CERTS_DIR}/${fqdn}"
    full="${dest}/fullchain.pem"
    key="${dest}/privkey.pem"
    mkdir -p "${dest}"
    if [[ -f "${full}" && -f "${key}" ]]; then
      continue
    fi
    tmpcnf="$(mktemp "${TMPDIR:-/tmp}/prefect-placeholder-XXXXXX.cnf")"
    cat >"${tmpcnf}" <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_req
prompt = no
[req_dn]
CN = ${fqdn}
[v3_req]
subjectAltName = DNS:${fqdn}
EOF
    # Fresh pair: remove any incomplete half so openssl can rewrite both.
    rm -f "${full}" "${key}"
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "${key}" \
      -out "${full}" \
      -days 365 \
      -config "${tmpcnf}" >/dev/null 2>&1
    rm -f "${tmpcnf}"
    chmod 0644 "${full}"
    chmod 0600 "${key}"
  done

  if [[ -n "${USER_NAME:-}" ]]; then
    chown -R "${USER_NAME}:${USER_NAME}" "${CERTS_DIR}" 2>/dev/null || true
  fi
}

# Write one Domain-front drop-in for a want-list FQDN (TLS server + :80 redirect).
# Idempotent: skips rewrite when on-disk bytes already match.
_edge_write_domain_front() {
  local fqdn="$1"
  local dest="${DOMAINS_DIR}/${fqdn}.conf"
  local desired tmp

  desired="$(cat <<EOF
# Domain front for ${fqdn} — Edge-owned (ADR-0028). Reconciled by ensure-components.
server {
    listen 80;
    listen [::]:80;
    server_name ${fqdn};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/acme;
        default_type text/plain;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${fqdn};

    ssl_certificate     /etc/nginx/certs/${fqdn}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/${fqdn}/privkey.pem;

    location = /healthcheck {
        default_type text/plain;
        return 200 'ok';
    }

    include /etc/nginx/prefect-routes/*--${fqdn}.conf;
}
EOF
)"

  if [[ -f "${dest}" ]] && [[ "$(cat "${dest}")" == "${desired}" ]]; then
    return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/prefect-domain-front-XXXXXX.conf")"
  printf '%s\n' "${desired}" >"${tmp}"
  install -m 0644 "${tmp}" "${dest}"
  rm -f "${tmp}"
}

# Reconcile Domain-front drop-ins for the want-list under DOMAINS_DIR (ADR-0028).
# Ensures Component stub 00-empty.conf and per-FQDN include stubs in ROUTES_DIR
# so nginx wildcard includes always match.
# Does not prune Domain fronts or Route stubs for names that left the want-list.
edge_reconcile_domain_fronts() {
  local fqdn stub
  local -a names=()

  mkdir -p "${DOMAINS_DIR}" "${ROUTES_DIR}"

  # Stub so include …/prefect-domains/*.conf matches when the want-list is empty.
  if [[ ! -f "${DOMAINS_DIR}/00-empty.conf" ]]; then
    printf '%s\n' '# no Domain fronts yet' >"${DOMAINS_DIR}/00-empty.conf"
  fi

  while IFS= read -r fqdn || [[ -n "${fqdn}" ]]; do
    [[ -n "${fqdn}" ]] || continue
    names+=("${fqdn}")
  done < <(_edge_want_list_fqdns)

  for fqdn in "${names[@]+"${names[@]}"}"; do
    _edge_write_domain_front "${fqdn}"
    # nginx rejects wildcard includes with zero matches; Edge-owned stub per FQDN.
    stub="${ROUTES_DIR}/00-empty--${fqdn}.conf"
    if [[ ! -f "${stub}" ]]; then
      printf '%s\n' "# Edge include stub for Domain front ${fqdn}" >"${stub}"
    fi
  done

  if [[ -n "${USER_NAME:-}" ]]; then
    chown -R "${USER_NAME}:${USER_NAME}" "${DOMAINS_DIR}" "${ROUTES_DIR}" 2>/dev/null || true
  fi
}
