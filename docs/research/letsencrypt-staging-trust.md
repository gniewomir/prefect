# How Acceptance Tests should trust Let’s Encrypt staging certs

**Researched:** 2026-07-28  
**Question:** What is the correct, primary-source way for an Acceptance Test client (typically curl/openssl from the operator or Host) to verify a certificate issued by Let’s Encrypt **staging**, so an HTTPS+/healthcheck proof can assert a real staging chain rather than accepting a self-signed placeholder or skipping verify?  
**Scope:** Let’s Encrypt official Staging Environment docs (roots, intermediates, trust guidance); curl man page / SSL CA docs; OpenSSL `s_client` / `verify` / verification-options docs. Not community forum anecdotes.

**Repo constraint:** Edge HTTPS+/healthcheck Acceptance proof uses live ACME against LE **staging** (not production). Edge may serve self-signed placeholder PEMs until ACME replaces them; the test must distinguish staging LE from placeholders without `-k` / `--insecure`.

---

## Verdict

| Recommendation | Implication for Acceptance Tests |
| --- | --- |
| Staging roots are **not** in browser/OS trust stores | Default `curl https://…` / default `openssl s_client` **fail** verify on real staging leaves (exit 60 / verify error 20) — that is expected, not a broken Edge |
| Trust **staging roots only** (test client CA store), not intermediates | Download the four official self-signed staging root PEMs from `letsencrypt.org/certs/staging/…` and pass them as the client trust anchors |
| Prefer **per-transfer custom CA** over installing staging roots into the system store | `curl --cacert <bundle.pem>` or `openssl … -CAfile <bundle.pem>` / `-verifyCAfile`; LE warns not to add staging roots to ordinary browsing trust stores |
| Do **not** pin or permanently trust staging **intermediates** | LE: intermediates “are subject to change at any time, and should not be pinned or trusted by any system”; the server sends them in the handshake for chain building |
| Do **not** use `--insecure` / `-k` (or openssl without verify-fail) | That accepts placeholders and MITM alike; curl documents `-k` as skipping peer verification |
| A multi-PEM file of the four **self-signed** staging roots is enough | curl `--cacert` and OpenSSL `-CAfile` both accept multiple PEM CAs in one file; cross-signed root PEMs are optional extras, not required trust anchors |
| Self-signed placeholders fail against that bundle | OpenSSL `verify` reports self-signed / unable to get issuer; that is how the proof distinguishes “ACME replaced PEMs” from create-if-missing placeholders |
| Gotcha: Apple **SecureTransport** curl may still succeed against production LE even when `--cacert` points at a staging-only bundle | For a strict “only staging roots” assert, prefer OpenSSL (`openssl s_client -CAfile … -verify_return_error`, or an OpenSSL-backed curl). Observed on stock macOS `curl 8.7.1 … (SecureTransport)` |

---

## Authoritative sources ranked

| Rank | Source | Owns |
| --- | --- | --- |
| 1 | [Let’s Encrypt — Staging Environment](https://letsencrypt.org/docs/staging-environment/) (last updated 2026-04-10 at research time) | Staging ACME URL; which roots exist; “add their certificates to your testing trust store”; do not add to ordinary trust stores; intermediates change / do not pin |
| 2 | Staging root PEM URLs under `https://letsencrypt.org/certs/staging/…` (linked from that page as Certificate details: **pem**) | Canonical bytes for trust anchors |
| 3 | [curl man page — `--cacert` / `--capath` / `--insecure`](https://curl.se/docs/manpage.html) + [TLS Certificate Verification](https://curl.se/docs/sslcerts.html) | How a test client points at a custom CA file; that `-k` skips verify; native vs file-based CA store behavior |
| 4 | [openssl-s_client(1)](https://docs.openssl.org/master/man1/openssl-s_client/), [openssl-verify(1)](https://docs.openssl.org/master/man1/openssl-verify/), [openssl-verification-options(1)](https://docs.openssl.org/master/man1/openssl-verification-options/) | `-CAfile` / `-verifyCAfile` trust anchors; `-untrusted` for intermediates; `-verify_return_error` so handshake fails on verify errors |

---

## Staging hierarchy (what to trust)

From [Staging Environment → Staging Certificate Hierarchy](https://letsencrypt.org/docs/staging-environment/):

- Staging **mimics** production but names are prefixed `(STAGING)` and are distinct.
- **Four active root CAs**, “not present in browser/client trust stores”:
  - `(STAGING) Pretend Pear X1` (RSA 4096)
  - `(STAGING) Bogus Broccoli X2` (ECDSA P-384)
  - `(STAGING) Yearning Yucca Root YE` (ECDSA P-384)
  - `(STAGING) Yonder Yam Root YR` (RSA 4096)
- LE’s prescribed client change: *“If you wish to modify a test-only client to trust the staging environment for testing purposes you can do so by adding their certificates to your testing trust store.”*
- Explicit safety note: *“Do not add the staging root or intermediate to a trust store that you use for ordinary browsing or other activities, since they are not audited or held to the same standards as our production roots…”*
- **Intermediates** (Pseudo Plum E5, …, Fake Farro YR3, …): *“These intermediates are subject to change at any time, and should not be pinned or trusted by any system.”* Full details are linked from the same page when needed; clients should build the chain from the handshake to a **root** trust anchor.

ACME directory for staging (same page): `https://acme-staging-v02.api.letsencrypt.org/directory`.

---

## Where to get the staging root PEMs

Linked from the Staging Environment page as Certificate details (**pem**) for each root. Confirmed HTTP 200 and subjects at research time:

| Root | Self-signed PEM (trust anchor) |
| --- | --- |
| Pretend Pear X1 | `https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem` |
| Bogus Broccoli X2 | `https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x2.pem` |
| Yearning Yucca Root YE | `https://letsencrypt.org/certs/staging/gen-y/root-ye.pem` |
| Yonder Yam Root YR | `https://letsencrypt.org/certs/staging/gen-y/root-yr.pem` |

Also published (same page): cross-signed forms (`letsencrypt-stg-root-x2-signed-by-x1.pem`, `gen-y/root-ye-by-x2.pem`, `gen-y/root-yr-by-x1.pem`). For a **trust store**, use the **self-signed** roots above; cross-signs are chain material, not additional required anchors if the issuing root is already trusted.

LE also publishes per-root test sites (`valid.` / `revoked.` / `expired.` × `x1` / `x2` / `ye` / `yr` under `*.staging-test-certs.letsencrypt.org`) useful for sanity-checking a test CA bundle before hitting Edge.

**Do not** treat older “Fake LE Root X1” / `acme-staging.api.letsencrypt.org` paths as current — the live Staging Environment page is the hierarchy of record.

---

## How curl verifies with a custom CA bundle

From the [curl man page](https://curl.se/docs/manpage.html) and [sslcerts.html](https://curl.se/docs/sslcerts.html):

- Default: curl verifies the peer (name match + signature chain to a CA in the store).
- Custom file: `--cacert <file>` — PEM file that **may contain multiple CA certificates**; used to verify the peer for that transfer. Env `CURL_CA_BUNDLE` is an alternative when the TLS backend is not Schannel.
- Directory form: `--capath <dir>` (OpenSSL-backed curl: PEMs + `c_rehash`).
- Skip verify: `-k` / `--insecure` — *“makes curl skip the verification step”*; documented as making the transfer insecure. **Not** acceptable for this proof.

Minimal Acceptance pattern:

```bash
# Build once (or vendor) a staging-roots-only bundle
cat \
  letsencrypt-stg-root-x1.pem \
  letsencrypt-stg-root-x2.pem \
  root-ye.pem \
  root-yr.pem \
  > le-staging-roots.pem

curl --fail --show-error \
  --cacert le-staging-roots.pem \
  "https://${FQDN}/healthcheck"
```

Observed against LE’s own staging `valid.*.staging-test-certs.letsencrypt.org` hosts: default trust → curl exit **60** (`unable to get local issuer certificate`); with `--cacert` staging-roots bundle → HTTP **200**, `ssl_verify_result=0`.

**Placeholder distinction:** a create-if-missing self-signed Edge cert is not signed by those staging roots, so the same `curl --cacert` call fails verify — without needing issuer-string scraping.

**macOS gotcha:** stock Apple curl here was `libcurl/8.7.1 (SecureTransport)`. With `--cacert` set to a staging-only bundle, staging `valid.x1…` verified as expected, but a **production** LE test host still reported `SSL certificate verify ok`. curl’s own docs distinguish native CA stores vs file-based verification and describe Apple SecTrust combinations where native trust may still apply unless you rely only on the file. For Acceptance that must reject non-staging chains, prefer **OpenSSL** verification (below) or an OpenSSL-linked curl, and treat SecureTransport `--cacert` as insufficiently isolating until proven otherwise on the Host image.

---

## How openssl verifies with a custom CA file

From [openssl-verification-options](https://docs.openssl.org/master/man1/openssl-verification-options/): `-CAfile` loads a file with one DER cert or **several PEM** trusted certificates.

From [openssl-s_client](https://docs.openssl.org/master/man1/openssl-s_client/):

- `-CAfile` / `-verifyCAfile` supply trust anchors for verifying the server certificate.
- By default `s_client` is a **test tool** that continues after verify errors; use **`-verify_return_error`** so verify failures abort the handshake.
- Intermediates presented by the server are used for chain building; you do not need to pin staging intermediates in `-CAfile`.

From [openssl-verify](https://docs.openssl.org/master/man1/openssl-verify/): `-CAfile` / `-trusted` for trust anchors; `-untrusted` for extra chain certs when verifying a saved leaf offline.

Live check pattern:

```bash
echo | openssl s_client \
  -connect "${FQDN}:443" \
  -servername "${FQDN}" \
  -CAfile le-staging-roots.pem \
  -verify_return_error
```

Observed: with the four-root bundle, `valid.x1.staging-test-certs.letsencrypt.org` → `Verification: OK` / return code 0; without `-CAfile` → verify error 20 (`unable to get local issuer certificate`). Offline: `openssl verify -CAfile le-staging-roots.pem -untrusted <intermediates.pem> <leaf.pem>` → `OK` for that staging leaf; a generated self-signed placeholder → error 18 (`self-signed certificate`); a production LE leaf against the staging-only `-CAfile` → error 20.

That OpenSSL path cleanly separates staging LE (pass) from placeholders and from production LE (fail) when the CA file contains only staging roots.

---

## Gotchas checklist

| Gotcha | Detail |
| --- | --- |
| Staging ≠ production trust | Staging roots are deliberately untrusted by default ([LE Staging](https://letsencrypt.org/docs/staging-environment/)) |
| Trust roots, not intermediates | Intermediates change; do not pin ([LE Staging](https://letsencrypt.org/docs/staging-environment/)) |
| Do not install into the operator’s daily trust store | LE: staging roots/intermediates are not audited like production |
| Bundle all four current self-signed roots | Any of X1 / X2 / YE / YR may issue depending on staging chain choice; LE documents all four as active |
| Prefer self-signed root PEMs as anchors | Cross-signed root PEMs exist; anchors are the self-signed files |
| `--insecure` / missing `-verify_return_error` | Accepts placeholders; defeats the proof |
| Apple SecureTransport curl + `--cacert` | May not isolate trust to the file alone; prefer OpenSSL for strict staging-only asserts |
| Hierarchy / filenames can evolve | Always re-read [Staging Environment](https://letsencrypt.org/docs/staging-environment/) before locking a vendor path; do not rely on obsolete “Fake LE Root X1” names |

---

## Implication for the #69 Acceptance proof (fact only)

Primary-source answer: configure the test client’s **TLS trust anchors** to the **official Let’s Encrypt staging root PEMs** (concatenated PEM bundle), verify HTTPS to `/healthcheck` **with verification enabled**. Success means the presented chain chains to a staging root (real staging issuance). Failure under that trust config is the correct outcome for self-signed placeholders and for non-staging CAs. Spec/implementation choices (where to vendor the PEMs, curl vs openssl on Host vs operator) are left to later tickets.

---

## Sources

- [Let’s Encrypt — Staging Environment](https://letsencrypt.org/docs/staging-environment/)
- Staging root PEMs: [x1](https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem), [x2](https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x2.pem), [ye](https://letsencrypt.org/certs/staging/gen-y/root-ye.pem), [yr](https://letsencrypt.org/certs/staging/gen-y/root-yr.pem)
- [curl man page](https://curl.se/docs/manpage.html) (`--cacert`, `--capath`, `--insecure`)
- [curl — TLS Certificate Verification](https://curl.se/docs/sslcerts.html)
- [openssl-s_client(1)](https://docs.openssl.org/master/man1/openssl-s_client/)
- [openssl-verify(1)](https://docs.openssl.org/master/man1/openssl-verify/)
- [openssl-verification-options(1)](https://docs.openssl.org/master/man1/openssl-verification-options/)
