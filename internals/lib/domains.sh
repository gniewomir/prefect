#!/usr/bin/env bash
# Domain assignment helpers (ADR-0021 / ADR-0023).
# Sourced by ensure-components, Adopt, and Domain unit tests.
#
# Requires REPO_ROOT to be set to the repository root (call-time).

# Print absolute path to the Domain assignment file for an Environment cloud slug.
# Prefers domains.override.json when present; otherwise domains.json (ADR-0021).
# Prints nothing and exits 0 when neither exists.
domains_assignment_path() {
  local slug="${1-}"
  if [[ -z "${slug}" ]]; then
    echo "FAIL: domains_assignment_path requires an Environment cloud slug" >&2
    return 1
  fi
  if [[ -z "${REPO_ROOT-}" ]]; then
    echo "FAIL: domains_assignment_path requires REPO_ROOT" >&2
    return 1
  fi
  local override="${REPO_ROOT}/config/environments/${slug}/domains.override.json"
  local committed="${REPO_ROOT}/config/environments/${slug}/domains.json"
  if [[ -f "${override}" ]]; then
    printf '%s\n' "${override}"
    return 0
  fi
  if [[ -f "${committed}" ]]; then
    printf '%s\n' "${committed}"
    return 0
  fi
  return 0
}

# Print ACME want-list FQDNs for an Environment cloud slug (one per line, sorted).
# Apex "@" → apex FQDN; other labels → <label>.<apex>.
# Missing assignment file → empty stdout, exit 0.
domains_acme_fqdns_for() {
  local slug="${1-}"
  if [[ -z "${slug}" ]]; then
    echo "FAIL: domains_acme_fqdns_for requires an Environment cloud slug" >&2
    return 1
  fi
  if [[ -z "${REPO_ROOT-}" ]]; then
    echo "FAIL: domains_acme_fqdns_for requires REPO_ROOT" >&2
    return 1
  fi
  local path
  path="$(domains_assignment_path "${slug}")" || return 1
  if [[ -z "${path}" ]]; then
    return 0
  fi
  python3 - "${path}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    raw = json.load(f)
if not isinstance(raw, dict):
    raise SystemExit(f"Domain assignment must be an object: {path}")

fqdns = set()
for apex, cfg in raw.items():
    if not isinstance(apex, str) or not apex:
        raise SystemExit(f"invalid Domain apex in {path}")
    if not isinstance(cfg, dict):
        raise SystemExit(f"Domain '{apex}' must be an object in {path}")
    names = cfg.get("names")
    if not isinstance(names, list) or not names:
        raise SystemExit(f"Domain '{apex}' must declare a non-empty names list in {path}")
    for name in names:
        if not isinstance(name, str) or not name:
            raise SystemExit(f"Domain '{apex}' has invalid name entry in {path}")
        if name == "@":
            fqdns.add(apex)
        else:
            fqdns.add(f"{name}.{apex}")

for fqdn in sorted(fqdns):
    print(fqdn)
PY
}
