#!/usr/bin/env bash
# Edge front-door readiness + reload (ADR-0015 / #134).
# Sourced by Edge Setup (wait after oneshot), Route install reload, and ACME post-issue settle.
# Optional: USER_NAME for ownership of systemctl --user; when sourced after
#           quadlet_user_session_begin, edge_reload_front_door restarts edge-pod if active.
# Test overrides: EDGE_FRONT_DOOR_WAIT_ATTEMPTS, EDGE_FRONT_DOOR_WAIT_SLEEP.

# Poll Host :80 until curl reports an HTTP status (any 3-digit code).
# Cold Edge start (image pull + nginx) and post-reload settle share this wait.
edge_wait_front_door() {
  local attempts="${EDGE_FRONT_DOOR_WAIT_ATTEMPTS:-60}"
  local sleep_s="${EDGE_FRONT_DOOR_WAIT_SLEEP:-2}"
  local _
  local code

  for _ in $(seq 1 "${attempts}"); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
    if [[ "${code}" =~ ^[0-9]{3}$ ]]; then
      return 0
    fi
    sleep "${sleep_s}"
  done
  echo "edge_wait_front_door: Edge did not answer on :80 in time" >&2
  return 1
}

# Restart edge-pod when active, then wait until :80 answers.
edge_reload_front_door() {
  local user="${USER_NAME:-platform}"
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u "${user}" 2>/dev/null || id -u)}"
  local -a cmd

  if [[ "$(id -un)" == "${user}" ]]; then
    cmd=(env "XDG_RUNTIME_DIR=${runtime}" systemctl --user)
  elif declare -F quadlet_user >/dev/null 2>&1; then
    cmd=(quadlet_user systemctl --user)
  else
    return 0
  fi

  if "${cmd[@]}" --quiet is-active edge-pod.service; then
    "${cmd[@]}" restart edge-pod.service
    "${cmd[@]}" --quiet is-active edge-pod.service
    edge_wait_front_door || {
      echo "edge_reload_front_door: Edge did not answer on :80 after restart" >&2
      return 1
    }
  fi
}
