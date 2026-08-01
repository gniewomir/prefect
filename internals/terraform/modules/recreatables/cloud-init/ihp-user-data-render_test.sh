#!/usr/bin/env bash
# Unit test: IHP user_data via production cloud-init/render module (ADR-0030 / ADR-0031).
# Asserts outcomes on the document Terraform delivers — not template/main.tf source shape.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
RENDER_MODULE="${REPO_ROOT}/internals/terraform/modules/recreatables/cloud-init/render"

# Known fixture inputs (independent of recreatables local.ssh_port twin).
SSH_PORT=9417
VOLUME_NAME="propraetor-test-web-data"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

command -v terraform >/dev/null || fail "terraform not found"
command -v ruby >/dev/null || fail "ruby not found (YAML parse)"

[[ -d "${RENDER_MODULE}" ]] || fail "missing render module at ${RENDER_MODULE}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/platform-ihp-ud.XXXXXX")"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

cat >"${WORKDIR}/main.tf" <<EOF
module "ihp_user_data" {
  source = "${RENDER_MODULE}"

  volume_name = "${VOLUME_NAME}"
  ssh_port    = ${SSH_PORT}
}

output "user_data" {
  value = module.ihp_user_data.user_data
}
EOF

terraform -chdir="${WORKDIR}" init -backend=false >/dev/null
terraform -chdir="${WORKDIR}" apply -input=false -auto-approve >/dev/null
terraform -chdir="${WORKDIR}" output -raw user_data >"${WORKDIR}/user_data.yaml"

# First non-empty line of each content: | block must be indented (not column 0).
if awk '
  /^[[:space:]]*content:[[:space:]]*\|[[:space:]]*$/ { want=1; next }
  want && NF { if ($0 !~ /^[[:space:]]/) { exit 1 } want=0 }
' "${WORKDIR}/user_data.yaml"; then
  pass "literal-block content lines are indented"
else
  fail "a content: | block has an unindented first line (indent() first-line trap)"
fi

ruby -ryaml -e "YAML.load_file('${WORKDIR}/user_data.yaml')" \
  || fail "rendered user_data is not valid YAML"
pass "rendered user_data parses as YAML"

ruby -ryaml -e "
ssh_port = ${SSH_PORT}
volume_name = '${VOLUME_NAME}'
d = YAML.load_file('${WORKDIR}/user_data.yaml')
files = d['write_files'] || []
by_path = files.map { |x| [x['path'], x] }.to_h

port = by_path['/etc/ssh/sshd_config.d/99-ssh-port.conf']
abort('missing Port drop-in') unless port
abort('Port drop-in wrong value') unless port['content'].to_s.include?(\"Port #{ssh_port}\")

script = by_path['/usr/local/lib/host-volume/ensure-host-volume-mount.sh']
abort('missing volume script') unless script
abort('volume script body missing shebang') unless script['content'].to_s.include?('#!/usr/bin/env bash')

unit = by_path['/etc/systemd/system/host-volume.service']
abort('missing host-volume.service') unless unit
unit_text = unit['content'].to_s
abort('unit missing Restart=on-failure') unless unit_text.include?('Restart=on-failure')
abort('unit missing StartLimitIntervalSec=300') unless unit_text.include?('StartLimitIntervalSec=300')

abort('missing tmpfiles WantedBy recipe') unless by_path['/etc/tmpfiles.d/host-volume.conf']
abort('missing udev late-attach rule') unless by_path['/etc/udev/rules.d/99-host-volume.rules']

abort('missing power_state reboot') unless d.dig('power_state', 'mode') == 'reboot'

runcmd = (d['runcmd'] || []).map(&:to_s).join(\"\\n\")
abort('runcmd must not wait/mount Host Volume scsi device') if runcmd.include?('scsi-0DO_Volume')

doc_lines = File.readlines('${WORKDIR}/user_data.yaml')
active = doc_lines.reject { |l| l.match?(/^\\s*#/) }.join
if active.match?(/sshd-socket-generator|ensure-ssh-listen|ssh\\.socket\\.d/)
  abort('must not mask generator or ship ssh.socket.d overrides')
end
" || fail "rendered user_data contract (ADR-0030 / ADR-0031)"
pass "rendered user_data matches IHP delivery contract"
