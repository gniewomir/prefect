#!/usr/bin/env bash
# Edge ACME on-demand runner (systemd user oneshot).
# Empty want-list → success with no CA contact.
# Non-empty → HTTP-01 via lego (staging by default), write PEMs, reload Edge (no Route projection).
# PREFECT_ACME_ISSUE=0 skips CA contact (Acceptance / fixture) but still reloads Edge when names exist.
# PREFECT_ACME_DIRECTORY=production opts into the Let's Encrypt production directory.
set -euo pipefail

DATA_ROOT=/var/lib/prefect/components_data/edge
ROUTES_DIR="${DATA_ROOT}/routes"
CERTS_DIR="${DATA_ROOT}/certs"
ACME_DIR="${DATA_ROOT}/acme"
ACME_WWW="${DATA_ROOT}/acme-www"
WANT_LIST="${ACME_DIR}/want-list"
LEGO_BIN="${LEGO_BIN:-/var/lib/prefect/components_data/edge/acme/bin/lego}"
USER_NAME="${PREFECT_USER:-prefect}"

# shellcheck source=../lib/quadlet-user-session.sh
source /var/lib/prefect/components/lib/quadlet-user-session.sh
# shellcheck source=../lib/edge-routes-host.sh
source /var/lib/prefect/components/lib/edge-routes-host.sh

mkdir -p "${ACME_DIR}" "${ACME_WWW}" "${CERTS_DIR}" "${ROUTES_DIR}"
[[ -f "${WANT_LIST}" ]] || : >"${WANT_LIST}"

mapfile -t names < <(grep -E -v '^[[:space:]]*(#|$)' "${WANT_LIST}" || true)
# Stamp every oneshot invocation so Acceptance Tests can observe triggers without a live CA.
date -u +%Y-%m-%dT%H:%M:%SZ >"${ACME_DIR}/last-run"

if ((${#names[@]} == 0)); then
  exit 0
fi

acme_server() {
  case "${PREFECT_ACME_DIRECTORY:-staging}" in
    production|prod)
      echo "https://acme-v02.api.letsencrypt.org/directory"
      ;;
    staging|*)
      echo "https://acme-staging-v02.api.letsencrypt.org/directory"
      ;;
  esac
}

install_pems_from_lego() {
  local host="$1"
  local crt="${ACME_DIR}/certificates/${host}.crt"
  local issuer="${ACME_DIR}/certificates/${host}.issuer.crt"
  local key="${ACME_DIR}/certificates/${host}.key"
  local dest="${CERTS_DIR}/${host}"
  [[ -f "${crt}" && -f "${key}" ]] || return 1
  mkdir -p "${dest}"
  if [[ -f "${issuer}" ]]; then
    cat "${crt}" "${issuer}" >"${dest}/fullchain.pem"
  else
    cp "${crt}" "${dest}/fullchain.pem"
  fi
  cp "${key}" "${dest}/privkey.pem"
  chmod 0644 "${dest}/fullchain.pem"
  chmod 0600 "${dest}/privkey.pem"
}

issue_one() {
  local host="$1"
  local email="${PREFECT_ACME_EMAIL:-}"
  local server
  server="$(acme_server)"
  # Let's Encrypt rejects .invalid and example.com contacts; default from the name's apex.
  if [[ -z "${email}" ]]; then
    if [[ "${host}" == *.*.* ]]; then
      email="acme@${host#*.}"
    else
      email="acme@${host}"
    fi
  fi

  # lego v5: flags are command options; `run` issues and renews (no separate renew).
  # Bound CA wait so a mispointed DNS name cannot stall the oneshot forever.
  # Do not bind :80/:443 — webroot only (Edge serves challenges).
  if ! timeout 120 "${LEGO_BIN}" run \
    --path "${ACME_DIR}" \
    --accept-tos \
    --email "${email}" \
    --server "${server}" \
    --domains "${host}" \
    --http \
    --http.webroot "${ACME_WWW}" \
    --renew-days 30; then
    echo "edge-acme: CA issue/renew failed for ${host} (leaving existing PEMs untouched)" >&2
    return 1
  fi
  install_pems_from_lego "${host}" || {
    echo "edge-acme: lego succeeded but PEMs missing for ${host}" >&2
    return 1
  }
}

# One-shot v4→v5 storage migrate (idempotent). lego prompts; answer yes non-interactively.
ensure_lego_storage() {
  if [[ ! -x "${LEGO_BIN}" ]]; then
    return 0
  fi
  printf 'y\n' | "${LEGO_BIN}" migrate --path "${ACME_DIR}" >/dev/null 2>&1 || true
}

issue_failed=0
if [[ "${PREFECT_ACME_ISSUE:-1}" != "0" ]]; then
  if [[ ! -x "${LEGO_BIN}" ]]; then
    echo "edge-acme: lego missing or not executable at ${LEGO_BIN}" >&2
    exit 1
  fi
  ensure_lego_storage
  for host in "${names[@]}"; do
    if ! issue_one "${host}"; then
      issue_failed=1
    fi
  done
else
  echo "edge-acme: PREFECT_ACME_ISSUE=0 — skipping CA contact; reloading Edge only" >&2
fi

# Oneshot runs as the Prefect User (systemd --user); only use root helpers when root.
if [[ "$(id -un)" == "${USER_NAME}" ]]; then
  UID_NUM="$(id -u)"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${UID_NUM}}"
else
  quadlet_user_session_begin
fi

# Operator-owned Routes are not rewritten; reload so new PEMs are picked up by existing Routes.
edge_reload_front_door

if [[ "${issue_failed}" -ne 0 ]]; then
  echo "edge-acme: one or more CA contacts failed; usable PEMs left untouched; Edge reloaded" >&2
fi
# Always succeed after reload attempt: DNS/CA failures are logged; Setup must not depend on issuance.
exit 0
