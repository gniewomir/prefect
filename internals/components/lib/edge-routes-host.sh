#!/usr/bin/env bash
# Edge Route install helpers (sourced by Edge Component Setup gather).
# Expects: ROUTES_DIR. Intent run also expects WANT_LIST (Host acme/want-list path).
# Optional: USER_NAME for ownership.
# Front-door reload lives in edge-front-door-host.sh (#134); this lib sources it so
# edge_reload_front_door_if_routes_changed can call the shared seam.
#
# Sets EDGE_ROUTES_CHANGED=1 when installed Route file contents for a reconcile/gather
# changed; else 0.
# ADR-0028: Routes are FQDN-keyed server-context snippets; Setup fails closed if a basename
# is not on the Domain want-list.
# ADR-0040: edge_gather_workload_routes collects Intent-run Declarations across Workload SoT.

_edge_routes_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=edge-want-list-host.sh
source "${_edge_routes_lib_dir}/edge-want-list-host.sh"
# shellcheck source=edge-front-door-host.sh
source "${_edge_routes_lib_dir}/edge-front-door-host.sh"

# Remove legacy projected `<name>.conf` and all `<name>--*` installed Routes for one Workload.
edge_remove_workload_installed_routes() {
  local wl_name="$1"
  local f
  rm -f "${ROUTES_DIR}/${wl_name}.conf"
  if compgen -G "${ROUTES_DIR}/${wl_name}--*" >/dev/null; then
    for f in "${ROUTES_DIR}/${wl_name}"--*; do
      rm -f "${f}"
    done
  fi
}

# True if exact FQDN (Route basename without .conf) is on the Host want-list.
_edge_route_fqdn_on_want_list() {
  local fqdn="$1"
  local candidate
  while IFS= read -r candidate || [[ -n "${candidate}" ]]; do
    [[ -n "${candidate}" ]] || continue
    [[ "${candidate}" == "${fqdn}" ]] && return 0
  done < <(edge_want_list_fqdns)
  return 1
}

# Validate every SoT *.conf basename against the want-list before mutating installs (ADR-0028).
_edge_validate_route_sot_want_list() {
  local sot_dir="$1"
  local src base fqdn

  for src in "${sot_dir}"/*; do
    [[ -f "${src}" ]] || continue
    base="$(basename "${src}")"
    [[ "${base}" == *.conf ]] || continue
    fqdn="${base%.conf}"
    if ! _edge_route_fqdn_on_want_list "${fqdn}"; then
      echo "edge_reconcile_workload_routes: Route basename '${fqdn}' is not on the Domain want-list" >&2
      return 1
    fi
  done
  return 0
}

# Fingerprint installed Route directory contents (paths + bytes), or "none".
_edge_routes_fingerprint() {
  local f
  local -a files=()

  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    files+=("${f}")
  done < <(find "${ROUTES_DIR}" -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort)

  if [[ ${#files[@]} -eq 0 ]]; then
    printf '%s\n' "none"
    return 0
  fi
  for f in "${files[@]}"; do
    printf '%s\0' "${f}"
    cat "${f}"
  done | sha256sum
}

# Reconcile one Workload's installed Routes from SoT dir (Intent run) or remove them.
# Args: workload_name intent routes_sot_dir
# routes_sot_dir may be missing/empty — zero Routes is valid for Intent run.
edge_reconcile_workload_routes() {
  local wl_name="$1"
  local intent="$2"
  local sot_dir="${3:-}"
  local routes_before routes_after
  local src base dest

  mkdir -p "${ROUTES_DIR}"
  EDGE_ROUTES_CHANGED=0

  if [[ "${intent}" == "run" && -n "${sot_dir}" && -d "${sot_dir}" ]]; then
    _edge_validate_route_sot_want_list "${sot_dir}" || return 1
  fi

  routes_before="$(_edge_routes_fingerprint)"

  edge_remove_workload_installed_routes "${wl_name}"

  if [[ "${intent}" == "run" && -n "${sot_dir}" && -d "${sot_dir}" ]]; then
    for src in "${sot_dir}"/*; do
      [[ -f "${src}" ]] || continue
      base="$(basename "${src}")"
      # Skip hidden / non-regular noise; Domain fronts include *--<fqdn>.conf
      [[ "${base}" == *.conf ]] || continue
      dest="${ROUTES_DIR}/${wl_name}--${base}"
      install -m 0644 "${src}" "${dest}"
    done
  fi

  if [[ -n "${USER_NAME:-}" ]]; then
    chown -R "${USER_NAME}:${USER_NAME}" "${ROUTES_DIR}" 2>/dev/null || true
  fi

  routes_after="$(_edge_routes_fingerprint)"
  if [[ "${routes_before}" != "${routes_after}" ]]; then
    EDGE_ROUTES_CHANGED=1
  fi
}

# Reload Edge only when installed Routes changed (avoids bouncing :80/:443 on no-op Setup).
edge_reload_front_door_if_routes_changed() {
  if [[ "${EDGE_ROUTES_CHANGED:-0}" == "1" ]]; then
    edge_reload_front_door
  fi
}

# Workload name encoded in an Edge interior Route basename (<wl>--<fqdn>.conf or legacy <wl>.conf).
_edge_installed_route_workload_name() {
  local base="$1"
  case "${base}" in
    *--*)
      printf '%s\n' "${base%%--*}"
      ;;
    *.conf)
      printf '%s\n' "${base%.conf}"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

# Read Manifest Intent (run|stop|trash). Prints Intent on stdout; fails closed otherwise.
_edge_read_workload_intent() {
  local manifest="$1"
  command -v python3 >/dev/null || {
    echo "edge_gather_workload_routes: python3 required to read Workload Manifest Intent" >&2
    return 1
  }
  python3 - "${manifest}" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
if not isinstance(m, dict):
    raise SystemExit("manifest must be a JSON object")
intent = m.get("intent")
if intent not in ("run", "stop", "trash"):
    raise SystemExit("manifest.intent must be run|stop|trash")
print(intent)
PY
}

# Gather Route Declarations from Workload Host Volume SoT and fulfill into Edge interior.
# Intent run → validate want-list and install; stop/trash → drop that Workload's fulfillment.
# Workloads missing from SoT leave orphan Edge installs, which are removed.
# Args: workloads_root (defaults to ambient WORKLOADS_ROOT).
# Sets EDGE_ROUTES_CHANGED=1 when the fulfilled Route set changed; else 0 (noop).
edge_gather_workload_routes() {
  local workloads_root="${1:-${WORKLOADS_ROOT-}}"
  local routes_before routes_after
  local wl_dir wl_name intent sot_dir f installed_wl

  if [[ -z "${workloads_root}" ]]; then
    echo "edge_gather_workload_routes: workloads root required (arg or WORKLOADS_ROOT)" >&2
    return 1
  fi

  mkdir -p "${ROUTES_DIR}"
  EDGE_ROUTES_CHANGED=0
  routes_before="$(_edge_routes_fingerprint)"

  if [[ -d "${workloads_root}" ]]; then
    for wl_dir in "${workloads_root}"/*; do
      [[ -d "${wl_dir}" && -f "${wl_dir}/manifest.json" ]] || continue
      wl_name="$(basename "${wl_dir}")"
      intent="$(_edge_read_workload_intent "${wl_dir}/manifest.json")" || return 1
      sot_dir="${wl_dir}/routes"
      if [[ ! -d "${sot_dir}" ]]; then
        sot_dir=""
      fi
      edge_reconcile_workload_routes "${wl_name}" "${intent}" "${sot_dir}" || return 1
    done
  fi

  # Drop fulfillments whose Workload SoT tree (with Manifest) is gone.
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    installed_wl="$(_edge_installed_route_workload_name "$(basename "${f}")")"
    [[ -n "${installed_wl}" ]] || continue
    if [[ ! -f "${workloads_root}/${installed_wl}/manifest.json" ]]; then
      rm -f "${f}"
    fi
  done < <(find "${ROUTES_DIR}" -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort)

  if [[ -n "${USER_NAME:-}" ]]; then
    chown -R "${USER_NAME}:${USER_NAME}" "${ROUTES_DIR}" 2>/dev/null || true
  fi

  routes_after="$(_edge_routes_fingerprint)"
  if [[ "${routes_before}" != "${routes_after}" ]]; then
    EDGE_ROUTES_CHANGED=1
  else
    EDGE_ROUTES_CHANGED=0
  fi
}
