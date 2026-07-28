#!/usr/bin/env bash
# Acceptance Test: Domain fronts + placeholder PEMs after ensure-components (#78)
# Tier A shape: /healthcheck + :80 redirect with insecure trust (Tier B is #79).
# No Workload Setup.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_ip
acceptance_ssh_opts
[[ -n "${REPO_ROOT:-}" ]] || fail "fixture missing REPO_ROOT (run via ./test.sh)"

# shellcheck source=../../lib/domains.sh
source "${REPO_ROOT}/lib/domains.sh"

DATA_ROOT=/var/lib/prefect/components_data/edge
DOMAINS_HOST="${DATA_ROOT}/domains"
CERTS_HOST="${DATA_ROOT}/certs"

EXPECTED="$(domains_acme_fqdns_for "${PREFECT_ENV:-test}")"
if [[ -z "${EXPECTED}" ]]; then
  echo "SOFT-SKIP: empty Domain want-list — no Domain fronts to assert (#78)"
  exit 0
fi

FQDN="$(printf '%s\n' "${EXPECTED}" | LC_ALL=C sort | head -n 1)"
[[ -n "${FQDN}" ]] || fail "want-list non-empty but no FQDN selected"

"${REPO_ROOT}/prefect/ensure-components.sh" --env "${PREFECT_ENV:-test}"

# --- Host layout: Domain front + placeholder PEMs ---
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f '${DOMAINS_HOST}/00-empty.conf'" \
  || fail "Domain-front Component stub missing"
ssh "${SSH_OPTS[@]}" "root@${IP}" "test -f '${DOMAINS_HOST}/${FQDN}.conf'" \
  || fail "Domain front missing for ${FQDN}"
ssh "${SSH_OPTS[@]}" "root@${IP}" \
  "test -f '${CERTS_HOST}/${FQDN}/fullchain.pem' && test -f '${CERTS_HOST}/${FQDN}/privkey.pem'" \
  || fail "placeholder PEMs missing for ${FQDN}"
front="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "cat '${DOMAINS_HOST}/${FQDN}.conf'")"
echo "${front}" | grep -Fq "include /etc/nginx/prefect-routes/*--${FQDN}.conf;" \
  || fail "Domain front must include Workload Route fragments for ${FQDN}"
pass "Domain front and placeholder PEMs present for ${FQDN}"

# Complete pair survives re-ensure (ADR-0029).
full_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${CERTS_HOST}/${FQDN}/fullchain.pem'")"
key_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${CERTS_HOST}/${FQDN}/privkey.pem'")"
front_before="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${DOMAINS_HOST}/${FQDN}.conf'")"
"${REPO_ROOT}/prefect/ensure-components.sh" --env "${PREFECT_ENV:-test}"
full_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${CERTS_HOST}/${FQDN}/fullchain.pem'")"
key_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${CERTS_HOST}/${FQDN}/privkey.pem'")"
front_after="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${DOMAINS_HOST}/${FQDN}.conf'")"
[[ "${full_before}" == "${full_after}" ]] || fail "re-ensure clobbered complete fullchain.pem"
[[ "${key_before}" == "${key_after}" ]] || fail "re-ensure clobbered complete privkey.pem"
[[ "${front_before}" == "${front_after}" ]] || fail "re-ensure churned Domain-front drop-in"
pass "re-ensure leaves complete PEMs and Domain-front drop-in untouched"

# --- Tier A: /healthcheck over HTTPS (placeholder trust) ---
HC_BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/prefect-hc-XXXXXX")"
trap 'rm -rf "${HC_BODY_FILE}"' EXIT
hc_code=""
hc_ctype=""
hc_body=""
for _ in $(seq 1 30); do
  hc_code="$(curl -skS -o "${HC_BODY_FILE}" -w '%{http_code}' --connect-timeout 10 --max-time 15 \
    --resolve "${FQDN}:443:${IP}" "https://${FQDN}/healthcheck" 2>/dev/null || true)"
  if [[ "${hc_code}" =~ ^[1-5][0-9]{2}$ ]]; then
    hc_ctype="$(curl -skS -o /dev/null -w '%{content_type}' --connect-timeout 10 --max-time 15 \
      --resolve "${FQDN}:443:${IP}" "https://${FQDN}/healthcheck" 2>/dev/null || true)"
    hc_body="$(cat "${HC_BODY_FILE}" 2>/dev/null || true)"
    break
  fi
  sleep 1
done
[[ "${hc_code}" == "200" ]] || fail "/healthcheck expected HTTP 200, got '${hc_code}'"
echo "${hc_ctype}" | grep -qi 'text/plain' \
  || fail "/healthcheck expected text/plain, got '${hc_ctype}'"
[[ "${hc_body}" == "ok" ]] || fail "/healthcheck expected body 'ok', got '${hc_body}'"
pass "Domain-front /healthcheck → 200 text/plain ok (no Workload)"

# --- :80 redirect ---
redir="$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --connect-timeout 10 --max-time 15 \
  --resolve "${FQDN}:80:${IP}" "http://${FQDN}/healthcheck")"
redir_code="${redir%% *}"
redir_url="${redir#* }"
[[ "${redir_code}" == "301" || "${redir_code}" == "302" ]] \
  || fail "expected redirect on :80 for Domain front, got '${redir}'"
echo "${redir_url}" | grep -q "^https://${FQDN}/healthcheck" \
  || fail "redirect target expected https://${FQDN}/healthcheck, got '${redir_url}'"
pass ":80 redirects non-ACME to HTTPS for Domain front"

# --- ACME HTTP-01 still works ---
TOKEN="domain-front-acme-probe"
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
TOKEN_PATH=${DATA_ROOT}/acme-www/.well-known/acme-challenge/${TOKEN}
mkdir -p "\$(dirname "\${TOKEN_PATH}")"
printf '%s\n' '${TOKEN}' >"\${TOKEN_PATH}"
chown -R prefect:prefect ${DATA_ROOT}/acme-www
REMOTE
# Retry: Edge may briefly RST during front-door reload (same window as /healthcheck).
acme_body=""
for _ in $(seq 1 30); do
  acme_body="$(curl -sS --connect-timeout 10 --max-time 15 \
    --resolve "${FQDN}:80:${IP}" "http://${FQDN}/.well-known/acme-challenge/${TOKEN}" 2>/dev/null || true)"
  [[ "${acme_body}" == "${TOKEN}" ]] && break
  sleep 1
done
[[ "${acme_body}" == "${TOKEN}" ]] || fail "ACME path on :80 broken after Domain front (got '${acme_body}')"
pass "ACME HTTP-01 on :80 still works alongside Domain-front redirect"

# --- ACME reload does not mutate Domain-front drop-in ---
front_pre_acme="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${DOMAINS_HOST}/${FQDN}.conf'")"
ssh "${SSH_OPTS[@]}" "root@${IP}" bash -s <<REMOTE
set -euo pipefail
UID_NUM="\$(id -u prefect)"
export XDG_RUNTIME_DIR="/run/user/\${UID_NUM}"
systemctl start "user@\${UID_NUM}.service"
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \
  systemctl --user stop edge-acme.service 2>/dev/null || true
runuser -u prefect -- env XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" PREFECT_ACME_ISSUE=0 \
  /var/lib/prefect/components/edge/acme-run.sh
REMOTE
front_post_acme="$(ssh "${SSH_OPTS[@]}" "root@${IP}" "sha256sum '${DOMAINS_HOST}/${FQDN}.conf'")"
[[ "${front_pre_acme}" == "${front_post_acme}" ]] \
  || fail "ACME must not mutate Domain-front drop-in"
pass "ACME reload leaves Domain-front drop-in unchanged"

echo "All Domain-front Acceptance checks passed."
