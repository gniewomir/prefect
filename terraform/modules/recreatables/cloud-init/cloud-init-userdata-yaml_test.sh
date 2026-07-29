#!/usr/bin/env bash
# Unit test: rendered IHP user_data must be valid YAML (cloud-init fails closed otherwise).
# Catches Terraform indent() leaving the first embedded script line at column 0.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TF_MAIN="${REPO_ROOT}/terraform/modules/recreatables/main.tf"
WEB_YAML="${REPO_ROOT}/terraform/modules/recreatables/cloud-init/web.yaml"
SCRIPT="${REPO_ROOT}/terraform/modules/recreatables/cloud-init/ensure-host-volume-mount.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

command -v terraform >/dev/null || fail "terraform not found"
command -v ruby >/dev/null || fail "ruby not found (YAML parse)"

grep -q 'format("\\n%s", file(' "${TF_MAIN}" \
  || fail "main.tf must indent(format(\"\\n%s\", file(...))) so the shebang is indented"
pass "embed uses leading-newline indent"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/prefect-ud-yaml.XXXXXX")"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

cat >"${WORKDIR}/main.tf" <<EOF
output "ud" {
  value = templatefile("${WEB_YAML}", {
    volume_name = "prefect-test-web-data"
    ssh_port    = 9417
    ensure_host_volume_mount_sh = indent(6, format("\\n%s", file("${SCRIPT}")))
  })
}
EOF

terraform -chdir="${WORKDIR}" init -backend=false >/dev/null
terraform -chdir="${WORKDIR}" apply -input=false -auto-approve >/dev/null
terraform -chdir="${WORKDIR}" output -raw ud >"${WORKDIR}/user_data.yaml"

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
d = YAML.load_file('${WORKDIR}/user_data.yaml')
paths = (d['write_files'] || []).map { |x| x['path'] }
abort('missing Port drop-in') unless paths.include?('/etc/ssh/sshd_config.d/99-prefect-port.conf')
abort('missing volume script') unless paths.include?('/usr/local/lib/prefect/ensure-host-volume-mount.sh')
abort('missing power_state reboot') unless d.dig('power_state', 'mode') == 'reboot'
" || fail "rendered user_data missing Port / volume script / power_state"
pass "rendered user_data includes Port, volume script, power_state reboot"
