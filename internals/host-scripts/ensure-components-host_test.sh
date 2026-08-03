#!/usr/bin/env bash
# Unit tests: ensure-components Host half — Component Setup only (ADR-0041 / #155).
# Offline: temp Host Volume roots + stub setup.sh scripts. No SSH / live Host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST_SCRIPT="${REPO_ROOT}/internals/host-scripts/ensure-components-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

inode_of() {
  local path="$1"
  if stat -f %i "${path}" >/dev/null 2>&1; then
    stat -f %i "${path}"
  else
    stat -c %i "${path}"
  fi
}

TMP="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/ensure-components.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
HV="${TMP}/host-volume"
mkdir -p "${HV}" "${TMP}/lib"
cp "${REPO_ROOT}/internals/host-scripts/lib/sync-tree-host.sh" "${TMP}/lib/sync-tree-host.sh"
printf '# ensure unit stub lib\n' >"${TMP}/lib/stub.sh"
printf '%s\n' 'alpha.example.test' >"${TMP}/platform-acme-want-list"

# Runnable copy with Host Volume + handoff paths redirected into TMP.
sed \
  -e "s|/var/lib/host-volume|${HV}|g" \
  -e "s|/tmp/platform-acme-want-list|${TMP}/want-handoff|g" \
  "${HOST_SCRIPT}" >"${TMP}/ensure-run.sh"
chmod +x "${TMP}/ensure-run.sh"

mkdir -p "${TMP}/edge" "${TMP}/fabric"
cat >"${TMP}/edge/setup.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "edge" >>"${TMP}/setup.order"
EOF
chmod +x "${TMP}/edge/setup.sh"
printf 'edge-nginx\n' >"${TMP}/edge/nginx.conf"
# Staged Fabric must be ignored by ensure-components.
cat >"${TMP}/fabric/setup.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "fabric" >>"${TMP}/setup.order"
EOF
chmod +x "${TMP}/fabric/setup.sh"

USER_NAME="$(id -un)"

# Offline macOS: Platform User group may not equal login name; Host uses user:user.
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/bin/chown"
export PATH="${TMP}/bin:${PATH}"

# --- Components only: installs Edge, runs Component Setup, ignores staged Fabric ---
: >"${TMP}/setup.order"
mkdir -p "${HV}/components/legacy" "${HV}/components_data/legacy"
bash "${TMP}/ensure-run.sh" "${USER_NAME}" --component edge 2>"${TMP}/stderr" \
  || fail "ensure-run failed: $(cat "${TMP}/stderr")"

grep -Fq 'Running Component Setup: edge' "${TMP}/stderr" \
  || fail "expected Component Setup log for edge, got: $(cat "${TMP}/stderr")"
if grep -Fq 'Running Fabric Setup' "${TMP}/stderr"; then
  fail "ensure-components must not run Fabric Setup"
fi
order="$(cat "${TMP}/setup.order")"
printf '%s\n' "${order}" | grep -Fxq 'edge' || fail "Component Setup did not run, got: ${order}"
if printf '%s\n' "${order}" | grep -Fxq 'fabric'; then
  fail "ensure-components must not run staged Fabric Setup"
fi
[[ -f "${HV}/internals/components/edge/setup.sh" ]] || fail "edge tree not installed on Host Volume"
[[ -f "${HV}/internals/components/edge/nginx.conf" ]] || fail "edge nginx.conf not installed"
[[ ! -e "${HV}/internals/fabric/setup.sh" ]] || fail "ensure-components must not install Fabric"
[[ -d "${HV}/internals/host-scripts/lib" ]] || fail "host-scripts lib not installed on Host Volume"
[[ -d "${HV}/internals/workloads" ]] || fail "workloads SoT root missing on Host Volume"
[[ -d "${HV}/data/components" ]] || fail "data/components missing on Host Volume"
[[ -d "${HV}/data/workloads" ]] || fail "data/workloads missing on Host Volume"
[[ ! -e "${HV}/components" ]] || fail "retired components/ must not exist after ensure"
[[ ! -e "${HV}/components_data" ]] || fail "retired components_data/ must not exist after ensure"
[[ ! -e "${HV}/internals/components/lib" ]] || fail "legacy components/lib must not exist after ensure"
# Want-list handoff is removed by the Host script trap on exit; reaching Setup proves it existed.
pass "ensure-components installs Components only and runs Component Setup"

# --- rejects --fabric (Fabric is a different cog; no combined ship) ---
if bash "${TMP}/ensure-run.sh" "${USER_NAME}" --fabric fabric 2>"${TMP}/stderr2"; then
  fail "expected failure for --fabric on ensure-components"
fi
grep -Eqi 'unknown argument|--component' "${TMP}/stderr2" \
  || fail "ensure-components --fabric rejection unclear: $(cat "${TMP}/stderr2")"
pass "ensure-components rejects --fabric (combined ship gone)"

# --- rejects bare positional list (hard cut; no dual argv) ---
if bash "${TMP}/ensure-run.sh" "${USER_NAME}" edge 2>"${TMP}/stderr3"; then
  fail "expected failure for legacy positional Component list"
fi
grep -Eqi 'unknown argument|--component' "${TMP}/stderr3" \
  || fail "legacy argv rejection unclear: $(cat "${TMP}/stderr3")"
pass "legacy positional Component list is rejected (no dual argv)"

# --- non-breaking ship: update Edge tree without replacing directory/file inodes ---
mkdir -p "${HV}/internals/components/edge"
printf 'old-nginx\n' >"${HV}/internals/components/edge/nginx.conf"
dir_ino="$(inode_of "${HV}/internals/components/edge")"
file_ino="$(inode_of "${HV}/internals/components/edge/nginx.conf")"
: >"${TMP}/setup.order"
bash "${TMP}/ensure-run.sh" "${USER_NAME}" --component edge 2>"${TMP}/stderr4" \
  || fail "re-ensure-components failed: $(cat "${TMP}/stderr4")"
[[ "$(inode_of "${HV}/internals/components/edge")" == "${dir_ino}" ]] \
  || fail "edge directory inode changed (breaking ship for bind mounts)"
[[ "$(inode_of "${HV}/internals/components/edge/nginx.conf")" == "${file_ino}" ]] \
  || fail "nginx.conf inode changed (file was unlinked instead of overwritten)"
grep -Fxq 'edge-nginx' "${HV}/internals/components/edge/nginx.conf" \
  || fail "nginx.conf content not updated in place"
pass "ensure-components updates Edge tree without replacing directory/file inodes"

# --- both cogs in order: Fabric then Components leave both installed ---
FABRIC_SCRIPT="${REPO_ROOT}/internals/host-scripts/ensure-fabric-host.sh"
sed -e "s|/var/lib/host-volume|${HV}|g" "${FABRIC_SCRIPT}" >"${TMP}/ensure-fabric-run.sh"
chmod +x "${TMP}/ensure-fabric-run.sh"
# Fresh HV for ordered run
rm -rf "${HV}"
mkdir -p "${HV}"
: >"${TMP}/setup.order"
bash "${TMP}/ensure-fabric-run.sh" "${USER_NAME}" --fabric fabric 2>"${TMP}/stderr5" \
  || fail "ordered ensure-fabric failed: $(cat "${TMP}/stderr5")"
bash "${TMP}/ensure-run.sh" "${USER_NAME}" --component edge 2>"${TMP}/stderr6" \
  || fail "ordered ensure-components failed: $(cat "${TMP}/stderr6")"
order="$(cat "${TMP}/setup.order")"
printf '%s\n' "${order}" | head -1 | grep -Fxq 'fabric' \
  || fail "Fabric Setup must run first when both cogs run in order, got: ${order}"
printf '%s\n' "${order}" | tail -1 | grep -Fxq 'edge' \
  || fail "Component Setup must run after Fabric when both cogs run in order, got: ${order}"
[[ -f "${HV}/internals/fabric/setup.sh" ]] || fail "fabric missing after ordered ensure"
[[ -f "${HV}/internals/components/edge/setup.sh" ]] || fail "edge missing after ordered ensure"
pass "ensure-fabric then ensure-components leaves Fabric and Edge installed in order"

echo "All ensure-components-host offline tests passed."
