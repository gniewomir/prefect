#!/usr/bin/env bash
# Environment Configuration bag resolution (operator-side; ADR-0035).
# Sourced by Workload Setup — not an operator entrypoint.
#
# environment_configuration_resolve MANIFEST ENV_DIR OUTFILE
#   Reads Manifest optional `environment` key names; resolves from ENV_DIR/.env
#   (strict dotenv subset) with shell overrides; writes KEY=value lines to OUTFILE.
#   Omit or [] → removes OUTFILE if present and returns 0 (no bag).
#   Non-empty list → OUTFILE always rewritten; missing keys / invalid dotenv fail closed.
# Prints WL_ENV_ACTIVE=0|1 on stdout for the caller to eval.

environment_configuration_resolve() {
  local manifest="${1:?manifest required}"
  local env_dir="${2:?env dir required}"
  local outfile="${3:?outfile required}"
  local dotenv="${env_dir}/.env"

  python3 - "${manifest}" "${dotenv}" "${outfile}" <<'PY'
import json, os, re, sys

manifest_path, dotenv_path, outfile = sys.argv[1], sys.argv[2], sys.argv[3]

with open(manifest_path, encoding="utf-8") as f:
    m = json.load(f)
if not isinstance(m, dict):
    raise SystemExit("manifest must be a JSON object")

if "environment" not in m:
    if os.path.exists(outfile):
        os.remove(outfile)
    print("WL_ENV_ACTIVE=0")
    raise SystemExit(0)

env = m["environment"]
if not isinstance(env, list):
    raise SystemExit("manifest.environment must be a JSON array when present")
keys = []
for i, item in enumerate(env):
    if not isinstance(item, str) or item == "":
        raise SystemExit(
            "manifest.environment elements must be non-empty strings "
            f"(bad index {i})"
        )
    keys.append(item)

if not keys:
    if os.path.exists(outfile):
        os.remove(outfile)
    print("WL_ENV_ACTIVE=0")
    raise SystemExit(0)

KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
file_vals = {}
if os.path.isfile(dotenv_path):
    with open(dotenv_path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if line.strip() == "" or line.lstrip().startswith("#"):
                continue
            if line.startswith("export ") or line.startswith("export\t"):
                raise SystemExit(
                    f"invalid dotenv at {dotenv_path}:{lineno}: export is not allowed"
                )
            if "=" not in line:
                raise SystemExit(
                    f"invalid dotenv at {dotenv_path}:{lineno}: expected KEY=value"
                )
            key, _, val = line.partition("=")
            if not KEY_RE.match(key):
                raise SystemExit(
                    f"invalid dotenv at {dotenv_path}:{lineno}: bad key name"
                )
            if "\n" in val or "\r" in val:
                raise SystemExit(
                    f"invalid dotenv at {dotenv_path}:{lineno}: multiline values are not allowed"
                )
            if val.startswith("'") and val.endswith("'") and len(val) >= 2:
                raise SystemExit(
                    f"invalid dotenv at {dotenv_path}:{lineno}: single-quoted values are not allowed"
                )
            if val.startswith('"') and val.endswith('"') and len(val) >= 2:
                val = val[1:-1]
            if "${" in val:
                raise SystemExit(
                    f"invalid dotenv at {dotenv_path}:{lineno}: interpolation is not allowed"
                )
            file_vals[key] = val

resolved = {}
missing = []
for key in keys:
    if key in os.environ:
        resolved[key] = os.environ[key]
    elif key in file_vals:
        resolved[key] = file_vals[key]
    else:
        missing.append(key)

if missing:
    raise SystemExit(
        "Environment Configuration missing keys (fail closed): " + ", ".join(missing)
    )

os.makedirs(os.path.dirname(outfile) or ".", exist_ok=True)
with open(outfile, "w", encoding="utf-8") as out:
    for key in keys:
        out.write(f"{key}={resolved[key]}\n")

print("WL_ENV_ACTIVE=1")
PY
}

# Fail closed when Manifest lists keys but the Workload tree has no quadlets/*.container.
environment_configuration_require_containers() {
  local tree="${1:?workload tree required}"
  local active="${2:?WL_ENV_ACTIVE required}"
  [[ "${active}" == "1" ]] || return 0
  local found=0
  local f
  if [[ -d "${tree}/quadlets" ]]; then
    for f in "${tree}/quadlets"/*.container; do
      [[ -f "${f}" ]] || continue
      found=1
      break
    done
  fi
  if [[ "${found}" -ne 1 ]]; then
    echo "Environment Configuration requires quadlets/*.container when environment is non-empty" >&2
    return 1
  fi
  return 0
}
