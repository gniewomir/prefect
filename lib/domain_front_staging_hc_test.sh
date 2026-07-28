#!/usr/bin/env bash
# Tier B OpenSSL Domain-front /healthcheck outcome (#79).
# Pure helper seam — no network, no openssl binary required.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=domain_front_staging_hc.sh
source "${REPO_ROOT}/lib/domain_front_staging_hc.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

OUT="$(mktemp "${TMPDIR:-/tmp}/prefect-stg-hc.XXXXXX")"
trap 'rm -f "${OUT}"' EXIT

# Staging-trusted 200 text/plain ok → success.
cat >"${OUT}" <<'EOF'
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Content-Length: 2
Connection: close

ok
EOF
domain_front_staging_hc_ok 0 "${OUT}" || fail "expected success for staging 200 ok"
pass "200 text/plain ok + exit 0 → success"

# Verify failure (non-zero openssl exit) → fail even with HTTP-looking body.
domain_front_staging_hc_ok 1 "${OUT}" && fail "non-zero exit must fail" || true
pass "non-zero openssl exit → fail"

# Wrong status.
cat >"${OUT}" <<'EOF'
HTTP/1.1 404 Not Found
Content-Type: text/plain

ok
EOF
domain_front_staging_hc_ok 0 "${OUT}" && fail "404 must fail" || true
pass "HTTP 404 → fail"

# Wrong content-type.
cat >"${OUT}" <<'EOF'
HTTP/1.1 200 OK
Content-Type: application/json

ok
EOF
domain_front_staging_hc_ok 0 "${OUT}" && fail "wrong content-type must fail" || true
pass "non-text/plain → fail"

# Wrong body.
cat >"${OUT}" <<'EOF'
HTTP/1.1 200 OK
Content-Type: text/plain

nope
EOF
domain_front_staging_hc_ok 0 "${OUT}" && fail "wrong body must fail" || true
pass "body not ok → fail"

# Placeholder / verify chatter with no HTTP → fail.
cat >"${OUT}" <<'EOF'
verify error:num=18:self-signed certificate
EOF
domain_front_staging_hc_ok 0 "${OUT}" && fail "no HTTP must fail" || true
pass "no HTTP response → fail"

echo "All domain_front_staging_hc_ok checks passed."
