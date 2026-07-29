#!/usr/bin/env bash
# Unit tests: IHP SSH Port + reboot cutover (ADR-0030 / DO documented path).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WEB_YAML="${REPO_ROOT}/terraform/modules/recreatables/cloud-init/web.yaml"
TF_MAIN="${REPO_ROOT}/terraform/modules/recreatables/main.tf"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "${WEB_YAML}" ]] || fail "missing ${WEB_YAML}"

grep -q 'sshd_config.d/99-prefect-port.conf' "${WEB_YAML}" \
  || fail "web.yaml must set sshd_config Port drop-in"
pass "installs sshd_config Port drop-in"

grep -q 'Port \${ssh_port}' "${WEB_YAML}" \
  || fail "Port drop-in must use templated ssh_port"
pass "Port uses templated ssh_port"

if ! grep -A10 '^power_state:' "${WEB_YAML}" | grep -q 'mode: reboot'; then
  fail "web.yaml must power_state reboot after Port (DO documented cutover)"
fi
pass "power_state reboots once for Port cutover"

# Mid-boot socket restarts / generator masks were the failed paths.
if grep -E 'sshd-socket-generator|ensure-ssh-listen|ssh\.socket\.d/' "${WEB_YAML}" \
  | grep -v '^[[:space:]]*#' >/dev/null; then
  fail "web.yaml must not mask generator or ship ssh.socket.d overrides"
fi
pass "no socket-generator mask or ListenStream override"

grep -q 'port_range.*=.*"22"' "${TF_MAIN}" \
  && fail "Firewall must not dual-allow classic :22 after proven cutover"
pass "Firewall does not allow classic :22"

# Only the Prefect twin port should appear as SSH inbound (not a bare "22" rule).
grep -q 'tostring(local.ssh_port)' "${TF_MAIN}" \
  || fail "Firewall SSH inbound must use tostring(local.ssh_port)"
pass "Firewall SSH inbound uses ssh_port twin"

grep -q 'format("\\n%s", file(' "${TF_MAIN}" \
  || fail "volume script embed must use indent(format(\"\\n%s\", file(...))) (YAML-safe)"
pass "volume script embed is YAML-safe"
