# Lifecycle Tests

Executable checks of Stack lifecycle operations that deliberately change Stack presence: **Park**, **Apply** after Park, and **Teardown**. Opt-in and destructive — may leave the Stack Parked or with empty State.

**Not Acceptance Tests.** `./test.sh` asserts a live Applied Stack and must not Park or Teardown. See `../test/README.md` and the glossary terms Acceptance Test / Lifecycle Test.

## Status

Park → Apply round-trip is covered (`10-park-apply.sh`). Teardown Lifecycle cases land with #28.

Apply fail-fast when Durable assumptions do not hold is not automated here — no safe reproduction without stranding billing or State.

## Run

Credentials must already be in the environment (`DIGITALOCEAN_TOKEN`, `TF_VAR_DIGITALOCEAN_PUBLIC_KEY` — same as `park.sh` / `teardown.sh`).

```bash
./lifecycle-test.sh              # all Lifecycle Tests, fail-fast
./lifecycle-test.sh park-apply   # one slice (substring match on the filename)
```

Optional: `VERIFY_SSH_IDENTITY=/path/to/private_key` if the default SSH agent/identities are not enough.

Expect explicit confirmation before Teardown cases (#28). Do not wire this into CI that assumes a standing Applied Stack.

## Add a case

1. Add `lifecycle-test/NN-short-name.sh`.
2. Use observable outcomes (provider presence, Reserved IP value, volume marker bytes, SSH reachability) — not Terraform internals.
3. Document leftover Stack state in the case header (Parked vs Applied vs empty).
4. Source `lib.sh` for `pass` / `fail`, provider Durable checks, and SSH helpers.

Non-case files in this directory (`lib.sh`, this README) are not executed.
