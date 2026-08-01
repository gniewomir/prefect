#!/usr/bin/env bash
# Operator Configuration + Provider Credential gates (ADR-0037 / ADR-0038).
# Sourced by operator entrypoints — not an entrypoint itself.
#
# Public:
#   provider_credential_require
#   operator_configuration_require both|private
#     Expand leading ~/ to $HOME; require absolute paths; set,exist,readable files.
#     both → public + private; private → private only. Exports expanded paths back
#     into the environment.
#   operator_configuration_export_host_root_ssh_public_key
#     Read public path content into TF_VAR_host_root_ssh_public_key (Apply → IHP).

provider_credential_require() {
  if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
    echo "FAIL: DIGITALOCEAN_TOKEN is not set (Provider Credential)" >&2
    return 1
  fi
  return 0
}

_operator_configuration_expand_path() {
  local raw="${1-}"
  if [[ -z "${raw}" ]]; then
    echo "operator configuration: empty path" >&2
    return 1
  fi
  # Match a literal ~/ prefix (do not tilde-expand the pattern — ADR-0038).
  # shellcheck disable=SC2088  # intentional: compare against literal '~/…'
  if [[ "${raw}" == '~/'* ]]; then
    printf '%s\n' "${HOME:?HOME is not set}/${raw#"~/"}"
    return 0
  fi
  if [[ "${raw}" == /* ]]; then
    printf '%s\n' "${raw}"
    return 0
  fi
  echo "operator configuration: path must be absolute or ~/… (got: ${raw})" >&2
  return 1
}

_operator_configuration_require_file() {
  local label="${1:?}"
  local path="${2:?}"
  if [[ ! -f "${path}" ]]; then
    echo "FAIL: ${label} is not a readable file: ${path}" >&2
    return 1
  fi
  if [[ ! -r "${path}" ]]; then
    echo "FAIL: ${label} is not readable: ${path}" >&2
    return 1
  fi
  return 0
}

operator_configuration_require() {
  local mode="${1:?operator_configuration_require requires both|private}"
  local pub priv

  case "${mode}" in
    both | private) ;;
    *)
      echo "operator_configuration_require: unknown mode '${mode}' (use both|private)" >&2
      return 1
      ;;
  esac

  if [[ "${mode}" == "both" ]]; then
    if [[ -z "${PROPRAETOR_PUBLIC_KEY_PATH:-}" ]]; then
      echo "FAIL: PROPRAETOR_PUBLIC_KEY_PATH is not set (Operator Configuration)" >&2
      return 1
    fi
    pub="$(_operator_configuration_expand_path "${PROPRAETOR_PUBLIC_KEY_PATH}")" || return 1
    _operator_configuration_require_file "PROPRAETOR_PUBLIC_KEY_PATH" "${pub}" || return 1
    PROPRAETOR_PUBLIC_KEY_PATH="${pub}"
    export PROPRAETOR_PUBLIC_KEY_PATH
  fi

  if [[ -z "${PROPRAETOR_PRIVATE_KEY_PATH:-}" ]]; then
    echo "FAIL: PROPRAETOR_PRIVATE_KEY_PATH is not set (Operator Configuration)" >&2
    return 1
  fi
  priv="$(_operator_configuration_expand_path "${PROPRAETOR_PRIVATE_KEY_PATH}")" || return 1
  _operator_configuration_require_file "PROPRAETOR_PRIVATE_KEY_PATH" "${priv}" || return 1
  PROPRAETOR_PRIVATE_KEY_PATH="${priv}"
  export PROPRAETOR_PRIVATE_KEY_PATH
  return 0
}

operator_configuration_export_host_root_ssh_public_key() {
  local path="${PROPRAETOR_PUBLIC_KEY_PATH-}"
  local content
  if [[ -z "${path}" ]]; then
    echo "FAIL: PROPRAETOR_PUBLIC_KEY_PATH is not set" >&2
    return 1
  fi
  content="$(tr -d '\r' <"${path}" | sed -n '1p')"
  if [[ -z "${content}" ]]; then
    echo "FAIL: public key file is empty: ${path}" >&2
    return 1
  fi
  export TF_VAR_host_root_ssh_public_key="${content}"
}
