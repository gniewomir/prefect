#!/usr/bin/env bash
# Environment Configuration bag resolution (operator-side; ADR-0035).
# Sourced by Workload Setup — not an operator entrypoint.
# Declaration shape + container gate: environment-configuration-declaration.sh (#129).
#
# environment_configuration_resolve MANIFEST ENV_DIR OUTFILE
#   Reads Manifest optional `environment` key names via the declaration surface;
#   resolves from ENV_DIR/.env (strict dotenv subset) with shell overrides;
#   writes KEY=value lines to OUTFILE.
#   Omit or [] → removes OUTFILE if present and returns 0 (no bag).
#   Non-empty list → OUTFILE always rewritten; missing keys / invalid dotenv fail closed.
# Prints WL_ENV_ACTIVE=0|1 on stdout for the caller to eval.

_ENVCFG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../components/lib/environment-configuration-declaration.sh
source "${_ENVCFG_LIB_DIR}/../components/lib/environment-configuration-declaration.sh"

environment_configuration_resolve() {
  local manifest="${1:?manifest required}"
  local env_dir="${2:?env dir required}"
  local outfile="${3:?outfile required}"
  local dotenv="${env_dir}/.env"
  local keys_file
  keys_file="$(mktemp "${TMPDIR:-/tmp}/envcfg-keys.XXXXXX")"

  if ! environment_configuration_keys "${manifest}" >"${keys_file}"; then
    rm -f "${keys_file}"
    return 1
  fi

  if [[ ! -s "${keys_file}" ]]; then
    rm -f "${keys_file}"
    if [[ -e "${outfile}" ]]; then
      rm -f "${outfile}"
    fi
    echo "WL_ENV_ACTIVE=0"
    return 0
  fi

  if ! python3 - "${dotenv}" "${outfile}" "${keys_file}" <<'PY'
import os, re, sys

dotenv_path, outfile, keys_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(keys_path, encoding="utf-8") as f:
    keys = [line.rstrip("\n") for line in f if line.rstrip("\n") != ""]

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
  then
    rm -f "${keys_file}"
    return 1
  fi
  rm -f "${keys_file}"
  return 0
}
