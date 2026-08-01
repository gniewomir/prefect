# Lifecycle Tests

Executable checks of Stack lifecycle operations that deliberately change Stack presence: **Park**, **Apply** after Park, and **Teardown**. Opt-in and destructive — may leave the Stack Parked or with empty State.

**Entrypoint:** `./test.sh lifecycle` — see [docs/agents/testing.md](../../../docs/agents/testing.md) (ADR-0036).

**Not Acceptance Tests.** Acceptance asserts a live Applied Stack and must not Park or Teardown. See `../acceptance/README.md` and the glossary terms Acceptance Test / Lifecycle Test / Unit Test.

## Status

- Stable Applied / Parked + Park → Apply round-trip: `10-park-apply.sh`
  (empty repeated Apply/Park plans; Cloud Project / Reserved IP / Host Volume /
  Domain identities; Host Volume marker; Host and Reserved IP memberships by
  lifecycle class)
- Parked Additive Domain happy path: `14-parked-additive-domain.sh`
  (case-owned Park; same override fixture as `15`; one normal Apply; prior Durables
  unchanged; fixture present; Recreatables restored; empty re-Apply; Teardown cleanup
  as in `15-additive-domain.sh`)
- Applied Additive Domain: `15-additive-domain.sh`
  (derived `domains.override.json` fixture; prior identities/memberships preserved;
  empty re-Apply; Teardown with override → drop override → committed re-Apply)
- Parked additive partial Apply recovery: `16-parked-additive-partial-apply.sh`
  (case-owned Park; same override fixture; Apply with invalid
  `TF_VAR_DIGITALOCEAN_PUBLIC_KEY` after Durable converge; restore key → Apply;
  empty re-Apply; Teardown cleanup as in `15-additive-domain.sh`)
- Subtractive Durable fail-closed: `17-subtractive-durable.sh`
  (narrower `domains.override.json` drops lex-first committed apex; Apply fails with
  `prevent_destroy`; Durables unchanged; drop override → committed re-Apply; empty re-Apply)
- Teardown from Parked (Durables wiped, State empty): `20-teardown.sh`
  (case-owned Park → Teardown; Cloud Project, Reserved IP, Host Volume, Domain when
  configured). Applied→Teardown remains covered by additive-case cleanup (`14`/`15`/`16`).

Domain Durable asserts run when Domains are in State (declare them in `environments/<cloud-slug>/domains.json` and Apply before the suite). With zero Domains configured, those asserts skip — Reserved IP / Host Volume coverage still runs. The Additive Domain case requires a non-empty committed Domain assignment (base apex for `lifecycle-test.<apex>`).

**Internal Domain override (maintainer / harness only):** if `environments/<slug>/domains.override.json` exists, production Domain loaders use it **instead of** `domains.json` (ADR-0021). Gitignored; not an operator flag. Additive Domain Lifecycle cases may write a derived override (committed map plus `lifecycle-test.<lexicographically-first-apex>`), run Apply/Teardown while it is present, then remove it before re-Apply of committed Domains only.

## Run

Credentials must already be in the environment (`DIGITALOCEAN_TOKEN`, `TF_VAR_DIGITALOCEAN_PUBLIC_KEY` — same as `./apply.sh` / `./park.sh` / `./teardown.sh`).

```bash
./test.sh lifecycle                 # all Lifecycle Tests on the test Environment (default)
./test.sh lifecycle park-apply      # one slice (substring match on the filename)
./test.sh lifecycle teardown        # Teardown wipe (prompts for exact 'teardown')
./test.sh lifecycle --env test      # same Environment as omitting --env (`default` also aliases)
./test.sh lifecycle --env prod      # Lifecycle against another Environment (explicit)
./test.sh lifecycle park-apply --env test
```

**Environment (ADR-0019):** same default-safe rule as Acceptance and other operator entrypoints — no `--env` → **test** (workspace `default`); `--env test` / `--env default` are aliases; any other slug requires explicit `--env <slug>`. When present, `--env` must be last. The runner propagates the resolved Environment into nested `./park.sh` / `./apply.sh` / `./teardown.sh` so child calls cannot flip Environment.

Optional: `VERIFY_SSH_IDENTITY=/path/to/private_key` if the default SSH agent/identities are not enough.

The runner asks for exact `teardown` before any Teardown case; the case also confirms into `./teardown.sh`. Do not wire this into CI that assumes a standing Applied Stack. After Teardown, leftover State is empty — `./apply.sh` again before `./test.sh acceptance`.

## Add a case

1. Add `NN-short-name.sh` in this directory.
2. Use observable outcomes (provider presence/absence, Reserved IP value, volume marker bytes, SSH reachability) — not Terraform internals. Exception: Teardown leftover emptiness may be asserted via empty State (glossary Teardown).
3. Document leftover Stack state in the case header (Parked vs Applied vs empty).
4. Source `lib.sh` for `pass` / `fail`, provider Durable checks, and SSH helpers.

Non-case files in this directory (`lib.sh`, `run.sh`, `*_test.sh`, this README) are not executed as cases.
