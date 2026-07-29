#!/usr/bin/env bash
# Fail if the Recreatable module cloud-init contains non-ASCII bytes.
# DigitalOcean can mojibake UTF-8 in user_data; YAML then rejects control
# characters (e.g. U+0086 from a mangled arrow) and drops the whole cloud-config.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLOUD_INIT_DIR="${REPO_ROOT}/internals/terraform/modules/recreatables/cloud-init"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -d "${CLOUD_INIT_DIR}" ]] || fail "missing ${CLOUD_INIT_DIR}"

hits=""
while IFS= read -r -d '' file; do
  file_hits="$(LC_ALL=C grep -n $'[\200-\377]' "${file}" || true)"
  if [[ -n "${file_hits}" ]]; then
    while IFS= read -r line; do
      hits+="${file}:${line}"$'\n'
    done <<<"${file_hits}"
  fi
done < <(find "${CLOUD_INIT_DIR}" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \) ! -name '*_test.sh' -print0 | sort -z)

if [[ -n "${hits}" ]]; then
  echo "FAIL: cloud-init must be ASCII-only (UTF-8 comments break DigitalOcean user_data):" >&2
  printf '%s' "${hits}" >&2
  exit 1
fi

pass "cloud-init user_data sources are ASCII-only"
