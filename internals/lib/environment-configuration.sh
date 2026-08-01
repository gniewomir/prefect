#!/usr/bin/env bash
# Environment Configuration module for Workload Setup / Purge (ADR-0035 / #132).
# Sourced by Workload Setup and offline tests — not an operator entrypoint.
#
# Public interface (Setup / Purge / offline tests):
#   environment_configuration_materialize MANIFEST ENV_DIR TREE WL_NAME
#     Resolve bag + gate once + materialize EnvironmentFile/drop-ins (in-process Host).
#   environment_configuration_clear WL_NAME
#     Remove EnvironmentFile tree + Setup-owned env drop-ins.
#   environment_configuration_stage_for_setup STAGE MANIFEST ENV_DIR TREE REMOTE_ROOT
#     SSH staging adapter: resolve+gate into STAGE; sets WL_ENV_ACTIVE and
#     WL_ENV_RESOLVED_REMOTE (under REMOTE_ROOT when active; empty when inactive).
#   environment_configuration_apply_resolved WL_NAME RESOLVED_SRC
#     Host half after staging (empty/unset → clear).
#
# Offline tests exercise materialize|clear|stage_for_setup. prepare / install_host are adapter internals.

_ENVCFG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=environment-configuration-declaration.sh
source "${_ENVCFG_LIB_DIR}/environment-configuration-declaration.sh"
# shellcheck source=../components/lib/workload-environment-host.sh
source "${_ENVCFG_LIB_DIR}/../components/lib/workload-environment-host.sh"

# Resolve Manifest environment keys from ENV_DIR/.env (strict dotenv) with shell
# overrides into OUTFILE. Omit/[] → remove OUTFILE, WL_ENV_ACTIVE=0.
# Prints WL_ENV_ACTIVE=0|1 on stdout for the caller to eval.
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
    printf 'WL_ENV_ACTIVE=0\n'
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

# Adapter internal: resolve + gate once. Writes OUTFILE when active.
# Prints WL_ENV_ACTIVE=0|1 on stdout for eval.
environment_configuration_prepare() {
  local manifest="${1:?manifest required}"
  local env_dir="${2:?env dir required}"
  local tree="${3:?workload tree required}"
  local outfile="${4:?outfile required}"
  local resolve_out

  resolve_out="$(environment_configuration_resolve "${manifest}" "${env_dir}" "${outfile}")" || return 1
  eval "${resolve_out}"
  environment_configuration_require_containers "${tree}" "${WL_ENV_ACTIVE}" || return 1
  printf '%s\n' "${resolve_out}"
}

# SSH staging adapter for Workload Setup: prepare into STAGE/environment.resolved
# and set WL_ENV_ACTIVE plus WL_ENV_RESOLVED_REMOTE (under REMOTE_ROOT when active).
# No stdout assignment protocol — callers read the globals after a successful return.
environment_configuration_stage_for_setup() {
  local stage="${1:?stage dir required}"
  local manifest="${2:?manifest required}"
  local env_dir="${3:?env dir required}"
  local tree="${4:?workload tree required}"
  local remote_root="${5:?remote stage root required}"
  local outfile="${stage}/environment.resolved"
  local prepare_out

  prepare_out="$(environment_configuration_prepare "${manifest}" "${env_dir}" "${tree}" "${outfile}")" || return 1
  eval "${prepare_out}"
  if [[ "${WL_ENV_ACTIVE}" == "1" ]]; then
    [[ -f "${outfile}" ]] || {
      echo "Environment Configuration resolve produced no file" >&2
      return 1
    }
    # Ambient for Workload Setup Host invoke (read after successful return).
    # shellcheck disable=SC2034  # intentional ambient output of this adapter
    WL_ENV_RESOLVED_REMOTE="${remote_root}/environment.resolved"
  else
    # shellcheck disable=SC2034  # intentional ambient output of this adapter
    WL_ENV_RESOLVED_REMOTE=""
  fi
  return 0
}

# Resolve+materialize for Setup (offline / in-process Host adapter).
environment_configuration_materialize() {
  local manifest="${1:?manifest required}"
  local env_dir="${2:?env dir required}"
  local tree="${3:?workload tree required}"
  local wl_name="${4:?workload name required}"
  local resolved prepare_out
  resolved="$(mktemp "${TMPDIR:-/tmp}/envcfg-resolved.XXXXXX")"

  prepare_out="$(environment_configuration_prepare "${manifest}" "${env_dir}" "${tree}" "${resolved}")" || {
    rm -f "${resolved}"
    return 1
  }
  eval "${prepare_out}"
  if [[ "${WL_ENV_ACTIVE}" == "1" ]]; then
    environment_configuration_apply_resolved "${wl_name}" "${resolved}" || {
      rm -f "${resolved}"
      return 1
    }
  else
    environment_configuration_apply_resolved "${wl_name}" "" || {
      rm -f "${resolved}"
      return 1
    }
  fi
  rm -f "${resolved}"
  return 0
}
