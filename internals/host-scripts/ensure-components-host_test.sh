#!/usr/bin/env bash
# Unit tests: ensure Host half — Fabric Setup then Component Setup (ADR-0040 / ADR-0041 / #154).
# Offline: temp Host Volume roots + stub setup.sh scripts. No SSH / live Host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST_SCRIPT="${REPO_ROOT}/internals/host-scripts/ensure-components-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ensure-components.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
HV="${TMP}/host-volume"
mkdir -p "${HV}" "${TMP}/lib"
printf '# ensure unit stub lib\n' >"${TMP}/lib/stub.sh"
printf '%s\n' 'alpha.example.test' >"${TMP}/platform-acme-want-list"

# Runnable copy with Host Volume + handoff paths redirected into TMP.
sed \
  -e "s|/var/lib/host-volume|${HV}|g" \
  -e "s|/tmp/platform-acme-want-list|${TMP}/want-handoff|g" \
  "${HOST_SCRIPT}" >"${TMP}/ensure-run.sh"
chmod +x "${TMP}/ensure-run.sh"

for name in fabric edge; do
  mkdir -p "${TMP}/${name}"
  cat >"${TMP}/${name}/setup.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "${name}" >>"${TMP}/setup.order"
EOF
  chmod +x "${TMP}/${name}/setup.sh"
done

USER_NAME="$(id -un)"

# Offline macOS: Platform User group may not equal login name; Host uses user:user.
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/bin/chown"
export PATH="${TMP}/bin:${PATH}"

# --- Fabric then Component order + ADR-0041 Host Volume layout ---
: >"${TMP}/setup.order"
# Seed retired layout; ensure must not leave it as the contract (hard cut).
mkdir -p "${HV}/components/legacy" "${HV}/components_data/legacy"
bash "${TMP}/ensure-run.sh" "${USER_NAME}" --fabric fabric --component edge 2>"${TMP}/stderr" \
  || fail "ensure-run failed: $(cat "${TMP}/stderr")"

grep -Fq 'Running Fabric Setup: fabric' "${TMP}/stderr" \
  || fail "expected Fabric Setup log for fabric, got: $(cat "${TMP}/stderr")"
grep -Fq 'Running Component Setup: edge' "${TMP}/stderr" \
  || fail "expected Component Setup log for edge, got: $(cat "${TMP}/stderr")"
if grep -Fq 'Running Component Setup: fabric' "${TMP}/stderr"; then
  fail "fabric must not be labeled Component Setup"
fi
order="$(cat "${TMP}/setup.order")"
printf '%s\n' "${order}" | head -1 | grep -Fxq 'fabric' \
  || fail "Fabric Setup (fabric) must run first, got: ${order}"
printf '%s\n' "${order}" | tail -1 | grep -Fxq 'edge' \
  || fail "Component Setup (edge) must run after Fabric, got: ${order}"
[[ -f "${HV}/internals/fabric/setup.sh" ]] || fail "fabric tree not installed on Host Volume"
[[ -f "${HV}/internals/components/edge/setup.sh" ]] || fail "edge tree not installed on Host Volume"
[[ -d "${HV}/internals/host-scripts/lib" ]] || fail "host-scripts lib not installed on Host Volume"
[[ -d "${HV}/internals/workloads" ]] || fail "workloads SoT root missing on Host Volume"
[[ -d "${HV}/data/fabric" ]] || fail "data/fabric missing on Host Volume"
[[ -d "${HV}/data/components" ]] || fail "data/components missing on Host Volume"
[[ -d "${HV}/data/workloads" ]] || fail "data/workloads missing on Host Volume"
[[ ! -e "${HV}/components" ]] || fail "retired components/ must not exist after ensure"
[[ ! -e "${HV}/components_data" ]] || fail "retired components_data/ must not exist after ensure"
[[ ! -e "${HV}/internals/components/lib" ]] || fail "legacy components/lib must not exist after ensure"
# Want-list handoff is removed by the Host script trap on exit; reaching Setup proves it existed.
pass "Fabric Setup then Component Setup with ADR-0041 Host Volume layout"

# --- rejects bare positional list (hard cut; no dual argv) ---
if bash "${TMP}/ensure-run.sh" "${USER_NAME}" fabric edge 2>"${TMP}/stderr2"; then
  fail "expected failure for legacy positional Component list"
fi
grep -Eqi 'unknown argument|--fabric|--component' "${TMP}/stderr2" \
  || fail "legacy argv rejection unclear: $(cat "${TMP}/stderr2")"
pass "legacy positional Component list is rejected (no dual argv)"

echo "All ensure-components-host offline tests passed."
