#!/usr/bin/env bash
# Host want-list FQDN reader + staged-list install (ADR-0023 / #131).
# Sourced by Domain fronts, Route reconcile, ACME, and Edge Setup.
# Expects: WANT_LIST (path to Host acme/want-list).
# Optional: USER_NAME for soft-fail chown (offline tests / non-root).

# Print non-comment want-list FQDNs, one per line.
# Missing WANT_LIST file → treat as empty (create empty file for later writers).
edge_want_list_fqdns() {
  local fqdn
  [[ -n "${WANT_LIST:-}" ]] || {
    echo "edge_want_list_fqdns: WANT_LIST is unset" >&2
    return 1
  }
  [[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"
  while IFS= read -r fqdn || [[ -n "${fqdn}" ]]; do
    [[ "${fqdn}" =~ ^[[:space:]]*(#|$) ]] && continue
    printf '%s\n' "${fqdn}"
  done <"${WANT_LIST}"
}

# Install operator-staged FQDN list into Host want-list location.
# Args: staged_path. When staged exists → install into WANT_LIST.
# Missing stage (Setup re-run without ensure-components) → leave existing WANT_LIST;
# create empty if absent. ensure-components fail-closes if stage is missing before Setup.
edge_install_want_list() {
  local staged="${1:-}"
  [[ -n "${WANT_LIST:-}" ]] || {
    echo "edge_install_want_list: WANT_LIST is unset" >&2
    return 1
  }
  mkdir -p "$(dirname "${WANT_LIST}")"
  if [[ -n "${staged}" && -f "${staged}" ]]; then
    install -m 0644 "${staged}" "${WANT_LIST}"
  else
    [[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"
  fi
  if [[ -n "${USER_NAME:-}" ]]; then
    chown "${USER_NAME}:${USER_NAME}" "${WANT_LIST}" 2>/dev/null || true
  fi
}
