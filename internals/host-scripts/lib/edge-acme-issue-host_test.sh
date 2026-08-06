#!/usr/bin/env bash
# Offline tests: ACME PEM vs configured directory mismatch → fresh issue (ADR-0045).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=edge-acme-issue-host.sh
source "${REPO_ROOT}/internals/host-scripts/lib/edge-acme-issue-host.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/edge-acme-issue.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

CERTS_DIR="${TMP}/certs"
ACME_DIR="${TMP}/acme"
HOST="example.test"
PEM_DIR="${CERTS_DIR}/${HOST}"
mkdir -p "${PEM_DIR}" "${ACME_DIR}/certificates"

make_issuer_pem() {
  local issuer_cn="$1"
  local out="$2"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${TMP}/key.pem" -out "${out}" -days 1 \
    -subj "/C=US/O=Let's Encrypt/CN=${issuer_cn}" >/dev/null 2>&1
}

# No PEM → not a mismatch (fresh issue path).
EDGE_ACME_DIRECTORY=production
if acme_installed_pem_wrong_ca "${HOST}"; then
  fail "missing PEM must not count as wrong-CA"
fi
pass "missing PEM is not wrong-CA"

# Staging issuer + production directory → mismatch.
make_issuer_pem "(STAGING) Baloney Bulgur YE2" "${PEM_DIR}/fullchain.pem"
EDGE_ACME_DIRECTORY=production
acme_installed_pem_wrong_ca "${HOST}" || fail "staging PEM vs production must mismatch"
pass "staging PEM vs production → wrong-CA"

# Staging issuer + staging directory → ok.
EDGE_ACME_DIRECTORY=staging
if acme_installed_pem_wrong_ca "${HOST}"; then
  fail "staging PEM vs staging must not mismatch"
fi
pass "staging PEM vs staging → ok"

# Production-like issuer + staging directory → mismatch.
make_issuer_pem "R13" "${PEM_DIR}/fullchain.pem"
EDGE_ACME_DIRECTORY=staging
acme_installed_pem_wrong_ca "${HOST}" || fail "production PEM vs staging must mismatch"
pass "production PEM vs staging → wrong-CA"

# Production issuer + production directory → ok.
EDGE_ACME_DIRECTORY=production
if acme_installed_pem_wrong_ca "${HOST}"; then
  fail "production PEM vs production must not mismatch"
fi
pass "production PEM vs production → ok"

# Placeholder / non-LE issuer → not treated as wrong-CA (normal issue replaces it).
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${TMP}/key.pem" -out "${PEM_DIR}/fullchain.pem" -days 1 \
  -subj "/CN=${HOST}" >/dev/null 2>&1
EDGE_ACME_DIRECTORY=production
if acme_installed_pem_wrong_ca "${HOST}"; then
  fail "self-signed placeholder must not count as wrong-CA"
fi
pass "placeholder PEM is not wrong-CA"

# clear lego cert removes host material, leaves other names.
printf 'crt\n' >"${ACME_DIR}/certificates/${HOST}.crt"
printf 'key\n' >"${ACME_DIR}/certificates/${HOST}.key"
printf 'other\n' >"${ACME_DIR}/certificates/other.example.test.crt"
acme_clear_lego_certificate "${HOST}" || fail "clear should succeed"
[[ ! -f "${ACME_DIR}/certificates/${HOST}.crt" ]] || fail "host crt must be removed"
[[ ! -f "${ACME_DIR}/certificates/${HOST}.key" ]] || fail "host key must be removed"
[[ -f "${ACME_DIR}/certificates/other.example.test.crt" ]] || fail "other cert must remain"
pass "acme_clear_lego_certificate removes only that host"

# acme-run: wrong-CA clears lego cert + no random sleep (not renew-force).
ACME_RUN="${REPO_ROOT}/internals/components/edge/acme-run.sh"
grep -Fq 'acme_installed_pem_wrong_ca' "${ACME_RUN}" \
  || fail "acme-run must consult wrong-CA helper"
grep -Fq 'acme_clear_lego_certificate' "${ACME_RUN}" \
  || fail "acme-run must clear lego cert on wrong-CA"
grep -Fq -- '--no-random-sleep' "${ACME_RUN}" \
  || fail "acme-run must disable lego renewal random sleep (Setup wait)"
if grep -Fq -- '--renew-force' "${ACME_RUN}"; then
  fail "acme-run must not use --renew-force (clear + fresh issue instead)"
fi
pass "acme-run wires wrong-CA → clear + --no-random-sleep"

echo "All edge-acme-issue-host offline tests passed."
