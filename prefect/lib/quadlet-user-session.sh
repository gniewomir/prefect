# Shared rootless Quadlet user-session helpers for Component Setup.
# Sourced on the Host only (not an operator entrypoint).
# Requires: USER_NAME (Prefect User login name)
# Exports: HOME_DIR, UID_NUM, UNIT_DIR, XDG_RUNTIME_DIR
#
# quadlet_user_session_begin  — resolve paths; ensure UNIT_DIR exists
# quadlet_user_session_reload — start user@, wait XDG_RUNTIME_DIR, daemon-reload
# quadlet_user CMD...         — runuser as Prefect User with XDG_RUNTIME_DIR

quadlet_user_session_begin() {
  id "${USER_NAME}" >/dev/null
  HOME_DIR="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
  UID_NUM="$(id -u "${USER_NAME}")"
  UNIT_DIR="${HOME_DIR}/.config/containers/systemd"
  mkdir -p "${UNIT_DIR}"
}

quadlet_user() {
  runuser -u "${USER_NAME}" -- env "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" "$@"
}

quadlet_user_session_reload() {
  systemctl start "user@${UID_NUM}.service"
  export XDG_RUNTIME_DIR="/run/user/${UID_NUM}"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -d "${XDG_RUNTIME_DIR}" ]] && break
    sleep 0.5
  done
  quadlet_user systemctl --user daemon-reload
}
