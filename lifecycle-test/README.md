# Lifecycle Tests

Executable checks of Stack lifecycle operations that deliberately change Stack presence: **Park**, **Apply** after Park, and **Teardown**. Opt-in and destructive — may leave the Stack Parked or with empty State.

**Not Acceptance Tests.** `./test.sh` asserts a live Applied Stack and must not Park or Teardown. See `../test/README.md` and the glossary terms Acceptance Test / Lifecycle Test.

## Status

- Park → Apply round-trip: `10-park-apply.sh` (Reserved IP, Host Volume marker, Domain when configured)
- Teardown (Durables wiped, State empty): `20-teardown.sh` (Reserved IP, Host Volume, Domain when configured)

Domain Durable asserts run when Domains are in State (configure `TF_VAR_domains` / `.tfvars` and Apply before the suite). With zero Domains configured, those asserts skip — Reserved IP / Host Volume coverage still runs.

Apply fail-fast when Durable assumptions do not hold is not automated here — no safe reproduction without stranding billing or State.

## Run

Credentials must already be in the environment (`DIGITALOCEAN_TOKEN`, `TF_VAR_DIGITALOCEAN_PUBLIC_KEY` — same as `./apply.sh` / `./park.sh` / `./teardown.sh`).

```bash
./lifecycle-test.sh                 # all Lifecycle Tests on the test Environment (default)
./lifecycle-test.sh park-apply      # one slice (substring match on the filename)
./lifecycle-test.sh teardown        # Teardown wipe (prompts for exact 'teardown')
./lifecycle-test.sh --env test      # same Environment as omitting --env (`default` also aliases)
./lifecycle-test.sh --env prod      # Lifecycle against another Environment (explicit)
```

**Environment (ADR-0019):** same default-safe rule as Acceptance and other operator entrypoints — no `--env` → **test** (workspace `default`); `--env test` / `--env default` are aliases; any other slug requires explicit `--env <slug>`. The runner propagates the resolved Environment into nested `./park.sh` / `./apply.sh` / `./teardown.sh` so child calls cannot flip Environment.

Optional: `VERIFY_SSH_IDENTITY=/path/to/private_key` if the default SSH agent/identities are not enough.

The runner asks for exact `teardown` before any Teardown case; the case also confirms into `./teardown.sh`. Do not wire this into CI that assumes a standing Applied Stack. After Teardown, leftover State is empty — `./apply.sh` again before `./test.sh`.

## Add a case

1. Add `lifecycle-test/NN-short-name.sh`.
2. Use observable outcomes (provider presence/absence, Reserved IP value, volume marker bytes, SSH reachability) — not Terraform internals. Exception: Teardown leftover emptiness may be asserted via empty State (glossary Teardown).
3. Document leftover Stack state in the case header (Parked vs Applied vs empty).
4. Source `lib.sh` for `pass` / `fail`, provider Durable checks, and SSH helpers.

Non-case files in this directory (`lib.sh`, this README) are not executed.
