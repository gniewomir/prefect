#!/usr/bin/env bash
# Environment ACME config → dotenv for Edge ACME (ADR-0045).
# Seam: acme_config_dotenv_for / acme_config_path.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=acme.sh
source "${REPO_ROOT}/internals/lib/acme/acme.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/acme-config.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
REPO_ROOT="${TMP}"

assert_dotenv() {
  local slug="$1"
  shift
  local -a want=("$@")
  local got
  local -a got_lines=()
  got="$(acme_config_dotenv_for "${slug}")" || fail "acme_config_dotenv_for '${slug}' exited non-zero"
  if [[ -n "${got}" ]]; then
    while IFS= read -r line; do
      got_lines+=("${line}")
    done <<<"${got}"
  fi
  local i
  [[ "${#got_lines[@]}" -eq "${#want[@]}" ]] \
    || fail "slug='${slug}': want ${#want[@]} lines (${want[*]}), got ${#got_lines[@]} (${got_lines[*]-})"
  for i in "${!want[@]}"; do
    [[ "${got_lines[$i]}" == "${want[$i]}" ]] \
      || fail "slug='${slug}' line ${i}: want '${want[$i]}', got '${got_lines[$i]}'"
  done
  pass "slug='${slug}' → ${want[*]}"
}

# Missing acme.json → staging only (no email; Host derives contact).
mkdir -p "${TMP}/environments/empty"
assert_dotenv empty 'EDGE_ACME_DIRECTORY=staging'

# Present production + email.
mkdir -p "${TMP}/environments/prodish"
printf '%s\n' '{"directory":"production","email":"ops@example.com"}' \
  >"${TMP}/environments/prodish/acme.json"
assert_dotenv prodish \
  'EDGE_ACME_DIRECTORY=production' \
  'EDGE_ACME_EMAIL=ops@example.com'

# staging is valid when explicit.
mkdir -p "${TMP}/environments/stagey"
printf '%s\n' '{"directory":"staging","email":"acme@stage.example"}' \
  >"${TMP}/environments/stagey/acme.json"
assert_dotenv stagey \
  'EDGE_ACME_DIRECTORY=staging' \
  'EDGE_ACME_EMAIL=acme@stage.example'

# Path helper: present → absolute path; missing → empty.
path="$(acme_config_path stagey)" || fail "acme_config_path stagey failed"
[[ "${path}" == "${TMP}/environments/stagey/acme.json" ]] \
  || fail "want stagey path, got '${path}'"
path="$(acme_config_path empty)" || fail "acme_config_path empty failed"
[[ -z "${path}" ]] || fail "empty env must yield empty path, got '${path}'"
pass "acme_config_path present vs missing"

# Fail closed: missing email when file present.
mkdir -p "${TMP}/environments/no-email"
printf '%s\n' '{"directory":"production"}' >"${TMP}/environments/no-email/acme.json"
if acme_config_dotenv_for no-email >/dev/null 2>"${TMP}/err-email"; then
  fail "missing email must fail closed"
fi
grep -Eqi 'email' "${TMP}/err-email" || fail "missing-email error unclear: $(cat "${TMP}/err-email")"
pass "missing email fails closed"

# Fail closed: bad directory.
mkdir -p "${TMP}/environments/bad-dir"
printf '%s\n' '{"directory":"live","email":"a@b.c"}' >"${TMP}/environments/bad-dir/acme.json"
if acme_config_dotenv_for bad-dir >/dev/null 2>"${TMP}/err-dir"; then
  fail "bad directory must fail closed"
fi
grep -Eqi 'directory|staging|production' "${TMP}/err-dir" \
  || fail "bad-directory error unclear: $(cat "${TMP}/err-dir")"
pass "bad directory fails closed"

# Fail closed: empty slug / missing REPO_ROOT.
if acme_config_dotenv_for >/dev/null 2>&1; then
  fail "empty slug must fail"
fi
unset REPO_ROOT
if acme_config_dotenv_for empty >/dev/null 2>&1; then
  fail "missing REPO_ROOT must fail"
fi
pass "slug and REPO_ROOT required"

echo "All acme_config helper checks passed."
