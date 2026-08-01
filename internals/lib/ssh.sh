# Shell twin of terraform/modules/recreatables local.ssh_port (ADR-0030).
# Sourced by operator SSH clients and Acceptance helpers. Keep the digit in sync
# with the Terraform local — mismatch locks the operator out.
# Host-session: bind/open once, then host_ssh / host_scp / host_session_ip.
# shellcheck disable=SC2034  # sourced constant; consumers use PLATFORM_SSH_PORT
PLATFORM_SSH_PORT=9417

# Ambient Host-session state (one session per process).
_HOST_SESSION_IP=""
_HOST_SESSION_PROFILE=""

# Reserved IP survives Host recreate; host keys do not. OpenSSH stores non-22
# ports as [host]:port — clearing only the bare IP leaves a stale entry that
# fails StrictHostKeyChecking=accept-new (accept-new does not replace mismatches).
propraetor_ssh_forget_host() {
  local ip="${1:?propraetor_ssh_forget_host requires IP}"
  ssh-keygen -R "${ip}" >/dev/null 2>&1 || true
  ssh-keygen -R "[${ip}]:${PLATFORM_SSH_PORT}" >/dev/null 2>&1 || true
}

_host_session_validate_profile() {
  case "${1-}" in
    operator | verify) return 0 ;;
    *)
      echo "host_session: unknown profile '${1-}' (use operator|verify)" >&2
      return 1
      ;;
  esac
}

# Bind an ambient Host-session to a known Reserved IP (Acceptance fixture path).
# Profiles: operator | verify (BatchMode). Identity: PROPRAETOR_PRIVATE_KEY_PATH.
host_session_bind() {
  local profile="${1:?host_session_bind requires profile}"
  local ip="${2:?host_session_bind requires IP}"
  _host_session_validate_profile "${profile}" || return 1
  [[ -n "${ip}" ]] || {
    echo "host_session_bind: empty IP" >&2
    return 1
  }
  _HOST_SESSION_PROFILE="${profile}"
  _HOST_SESSION_IP="${ip}"
}

# Open an ambient Host-session from Stack State (terraform output reserved_ip).
# Caller must have environment_activate'd; stack_dir is the Terraform root.
host_session_open() {
  local profile="${1:?host_session_open requires profile}"
  local stack_dir="${2:?host_session_open requires stack_dir}"
  local ip
  _host_session_validate_profile "${profile}" || return 1
  [[ -d "${stack_dir}" ]] || {
    echo "host_session_open: stack_dir is not a directory: ${stack_dir}" >&2
    return 1
  }
  ip="$(
    cd "${stack_dir}" || exit 1
    terraform output -raw reserved_ip 2>/dev/null || true
  )"
  [[ -n "${ip}" ]] || {
    echo "host_session_open: no reserved_ip output (apply the Stack first)" >&2
    return 1
  }
  host_session_bind "${profile}" "${ip}"
}

# Print the bound/opened Reserved IP. Fails closed if no ambient session.
host_session_ip() {
  [[ -n "${_HOST_SESSION_IP}" ]] || {
    echo "host_session_ip: no Host-session (call host_session_open or host_session_bind first)" >&2
    return 1
  }
  printf '%s\n' "${_HOST_SESSION_IP}"
}

# Populate _HOST_SESSION_OPTS from ambient profile. Fails closed if no session.
_host_session_build_opts() {
  local identity=""
  [[ -n "${_HOST_SESSION_IP}" && -n "${_HOST_SESSION_PROFILE}" ]] || {
    echo "host_session: no Host-session (call host_session_open or host_session_bind first)" >&2
    return 1
  }
  _HOST_SESSION_OPTS=(-o "Port=${PLATFORM_SSH_PORT}" -o StrictHostKeyChecking=accept-new)
  case "${_HOST_SESSION_PROFILE}" in
    verify)
      _HOST_SESSION_OPTS+=(
        -o BatchMode=yes
        -o ConnectTimeout=10
        -o PreferredAuthentications=publickey
      )
      ;;
    operator) ;;
  esac
  identity="${PROPRAETOR_PRIVATE_KEY_PATH:-}"
  if [[ -n "${identity}" ]]; then
    _HOST_SESSION_OPTS+=(-i "${identity}" -o IdentitiesOnly=yes)
  fi
}

# Run ssh against the ambient Host-session (payload args only).
host_ssh() {
  _host_session_build_opts || return 1
  ssh "${_HOST_SESSION_OPTS[@]}" "root@${_HOST_SESSION_IP}" "$@"
}

# scp local_path to root@IP:remote_path using the ambient Host-session.
host_scp() {
  local local_path="${1:?host_scp requires local_path}"
  local remote_path="${2:?host_scp requires remote_path}"
  _host_session_build_opts || return 1
  scp "${_HOST_SESSION_OPTS[@]}" "${local_path}" "root@${_HOST_SESSION_IP}:${remote_path}"
}
