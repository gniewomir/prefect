#!/usr/bin/env bash
# Host want-list FQDN iterator (ADR-0023). Sourced by Domain fronts and Route reconcile.
# Expects: WANT_LIST (path to Host acme/want-list).

# Print non-comment want-list FQDNs, one per line.
# Missing WANT_LIST file → treat as empty (create empty file for later writers).
_edge_want_list_fqdns() {
  local fqdn
  [[ -n "${WANT_LIST:-}" ]] || {
    echo "_edge_want_list_fqdns: WANT_LIST is unset" >&2
    return 1
  }
  [[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"
  while IFS= read -r fqdn || [[ -n "${fqdn}" ]]; do
    [[ "${fqdn}" =~ ^[[:space:]]*(#|$) ]] && continue
    printf '%s\n' "${fqdn}"
  done <"${WANT_LIST}"
}
