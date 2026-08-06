#!/usr/bin/env bash
# Host ACME EnvironmentFile install from staged dotenv (ADR-0045).
# Sourced by Edge Setup. Expects: ACME_ENV (path to Host acme/environment).
# Optional: USER_NAME for soft-fail chown (offline tests / non-root).

# Install operator-staged ACME dotenv into Host EnvironmentFile location.
# Args: staged_path. When staged exists → install into ACME_ENV.
# Missing stage (Setup re-run without ensure-components) → leave existing ACME_ENV;
# create staging-only default if absent.
edge_install_acme_env() {
  local staged="${1:-}"
  [[ -n "${ACME_ENV:-}" ]] || {
    echo "edge_install_acme_env: ACME_ENV is unset" >&2
    return 1
  }
  mkdir -p "$(dirname "${ACME_ENV}")"
  if [[ -n "${staged}" && -f "${staged}" ]]; then
    install -m 0644 "${staged}" "${ACME_ENV}"
  else
    if [[ ! -f "${ACME_ENV}" ]]; then
      printf 'EDGE_ACME_DIRECTORY=staging\n' >"${ACME_ENV}"
      chmod 0644 "${ACME_ENV}"
    fi
  fi
  if [[ -n "${USER_NAME:-}" ]]; then
    chown "${USER_NAME}:${USER_NAME}" "${ACME_ENV}" 2>/dev/null || true
  fi
}
