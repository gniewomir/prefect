#!/usr/bin/env bash
# Domain assignment helpers (ADR-0021 / ADR-0023).
# Sourced by local checks (lib/domains_acme_fqdns_test.sh) and later by the
# ACME want-list cutover (#56 / ensure-components).
#
# Requires REPO_ROOT to be set to the repository root (call-time).

# Print ACME want-list FQDNs for an Environment cloud slug (one per line, sorted).
# Apex "@" → apex FQDN; other labels → <label>.<apex>.
# Missing domains.json → empty stdout, exit 0.
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
  local path="${REPO_ROOT}/config/environments/${slug}/domains.json"
  if [[ ! -f "${path}" ]]; then
    return 0
  fi
  python3 - "${path}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    raw = json.load(f)
if not isinstance(raw, dict):
    raise SystemExit(f"domains.json must be an object: {path}")

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
