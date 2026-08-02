#!/usr/bin/env bash
# Deep Edge Component Setup (ADR-0023 / ADR-0028 / ADR-0040 / #137).
# Sourced by Edge setup.sh. Success meaning: Domains present, Edge units active,
# front door answers, Intent-run Route Declarations fulfilled. Want-list install,
# placeholders, Domain fronts, Route gather, oneshot, and wait are implementation
# behind this interface — not a caller checklist.
#
# Ambient (optional overrides for offline tests):
#   USER_NAME, DATA_ROOT  — Host Volume Edge data root defaults apply when unset.
# After begin: HOME_DIR / UNIT_DIR / SYSTEMD_USER_DIR via quadlet_user_session_begin.
#
# Args: component_tree  staged_want_list_src
# Staging pathname is an argument only at this seam (and edge_install_want_list).
# Returns 0 only when Domain presence is reconciled and front door answers.

_edge_setup_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=quadlet-user-session.sh
source "${_edge_setup_lib_dir}/quadlet-user-session.sh"
# shellcheck source=edge-want-list-host.sh
source "${_edge_setup_lib_dir}/edge-want-list-host.sh"
# shellcheck source=edge-domain-fronts-host.sh
source "${_edge_setup_lib_dir}/edge-domain-fronts-host.sh"
# shellcheck source=edge-front-door-host.sh
source "${_edge_setup_lib_dir}/edge-front-door-host.sh"
# shellcheck source=edge-routes-host.sh
source "${_edge_setup_lib_dir}/edge-routes-host.sh"
# shellcheck source=component-units-host.sh
source "${_edge_setup_lib_dir}/component-units-host.sh"

# Deep Edge Setup success: Domains present + Edge units active + front door answers.
# Args: component_tree  staged_want_list_src
edge_setup() {
  local component_tree="${1:?edge_setup: component tree required}"
  local staged_want_list="${2:-}"

  USER_NAME="${USER_NAME:-platform}"
  DATA_ROOT="${DATA_ROOT:-/var/lib/host-volume/components_data/edge}"
  ROUTES_DIR="${DATA_ROOT}/routes"
  DOMAINS_DIR="${DATA_ROOT}/domains"
  CERTS_DIR="${DATA_ROOT}/certs"
  ACME_WWW="${DATA_ROOT}/acme-www"
  ACME_DIR="${DATA_ROOT}/acme"
  WANT_LIST="${ACME_DIR}/want-list"

  quadlet_user_session_begin

  mkdir -p "${ROUTES_DIR}" "${DOMAINS_DIR}" "${CERTS_DIR}" "${ACME_WWW}" "${ACME_DIR}"
  # Staged by ensure-components; Edge owns Host want-list path (ADR-0023 / #131).
  edge_install_want_list "${staged_want_list}"

  component_units_install "${component_tree}"
  chmod a+x "${component_tree}/acme-run.sh"

  # Placeholders before Domain fronts that reference those paths (ADR-0029).
  # Domain-front reconcile also drops legacy 00-empty include stubs (empty globs OK).
  edge_plant_placeholder_pems
  edge_reconcile_domain_fronts

  # Route Declarations: gather Intent-run SoT into Edge interior (ADR-0040).
  # Workload Setup/Purge do not write Edge routes; refresh by re-running Edge Setup.
  WORKLOADS_ROOT="${WORKLOADS_ROOT:-$(dirname "${DATA_ROOT}")/workloads}"
  edge_gather_workload_routes "${WORKLOADS_ROOT}" || return 1

  chown -R "${USER_NAME}:${USER_NAME}" \
    "${HOME_DIR}/.config" \
    "${DATA_ROOT}"

  [[ -f "${component_tree}/nginx.conf" ]] || {
    echo "Edge nginx.conf missing at ${component_tree}/nginx.conf" >&2
    return 1
  }
  [[ -x "${component_tree}/acme-run.sh" ]] || {
    echo "Edge acme-run.sh missing or not executable at ${component_tree}/acme-run.sh" >&2
    return 1
  }

  # Install lego under Edge ACME data (survives Component tree refresh).
  local LEGO_VERSION="v5.3.1"
  local LEGO_DIR="${ACME_DIR}/bin"
  local LEGO_BIN="${LEGO_DIR}/lego"
  if [[ ! -x "${LEGO_BIN}" ]] || ! "${LEGO_BIN}" --version 2>/dev/null | grep -Fq "${LEGO_VERSION#v}"; then
    local arch lego_arch tmp url
    arch="$(uname -m)"
    case "${arch}" in
      x86_64 | amd64) lego_arch="amd64" ;;
      aarch64 | arm64) lego_arch="arm64" ;;
      *)
        echo "Edge ACME: unsupported architecture for lego: ${arch}" >&2
        return 1
        ;;
    esac
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/platform-lego.XXXXXX")"
    url="https://github.com/go-acme/lego/releases/download/${LEGO_VERSION}/lego_${LEGO_VERSION}_linux_${lego_arch}.tar.gz"
    echo "Edge ACME: installing lego ${LEGO_VERSION} (${lego_arch})" >&2
    curl -fsSL "${url}" -o "${tmp}/lego.tgz"
    tar -xzf "${tmp}/lego.tgz" -C "${tmp}" lego
    mkdir -p "${LEGO_DIR}"
    install -m 0755 "${tmp}/lego" "${LEGO_BIN}"
    rm -rf "${tmp}"
  fi
  [[ -x "${LEGO_BIN}" ]] || {
    echo "Edge ACME: lego not installed at ${LEGO_BIN}" >&2
    return 1
  }

  chown -R "${USER_NAME}:${USER_NAME}" "${DATA_ROOT}"

  quadlet_user_session_reload
  quadlet_user systemctl --user reset-failed edge-pod.service edge-nginx.service edge-acme.service 2>/dev/null || true
  # Quadlet: edge.pod → edge-pod.service (pulls Service Network + edge-nginx).
  quadlet_user systemctl --user restart edge-pod.service
  quadlet_user systemctl --user --quiet is-active edge-pod.service

  # On-demand ACME capability: timer armed even with an empty want-list (ADR-0015).
  quadlet_user systemctl --user enable --now edge-acme.timer
  quadlet_user systemctl --user --quiet is-active edge-acme.timer
  # Block until the oneshot finishes: acme-run reloads the Edge front door at the end,
  # so returning early races Acceptance/operator HTTP on :80/:443. CA/DNS failures still
  # soft-succeed (oneshot exit 0 — ADR-0012 / ADR-0015). restart (not start): re-ensure
  # must re-run oneshot even if a prior oneshot is still active.
  quadlet_user systemctl --user restart edge-acme.service

  # Shared front-door wait (post-ACME reload / empty want-list / image pull + nginx) — #134.
  if ! edge_wait_front_door; then
    quadlet_user systemctl --user status edge-pod.service edge-nginx.service edge-acme.service --no-pager >&2 || true
    return 1
  fi
}
