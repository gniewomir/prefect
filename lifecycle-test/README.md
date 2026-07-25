# Lifecycle Tests

Executable checks of Stack lifecycle operations that deliberately change Stack presence: **Park**, **Apply** after Park, and **Teardown**. Opt-in and destructive — may leave the Stack Parked or with empty State.

**Not Acceptance Tests.** `./test.sh` asserts a live Applied Stack and must not Park or Teardown. See `../test/README.md` and the glossary terms Acceptance Test / Lifecycle Test.

## Status

Scaffold only until Park / Teardown / Apply-after-Park are implemented. Cases will land with that work (marker bytes on Host Volume, same Reserved IP across Park→Apply, Durables gone after Teardown, fail-fast when Durable assumptions do not hold).

## Run (planned)

```bash
./lifecycle-test.sh              # all Lifecycle Tests, fail-fast
./lifecycle-test.sh park-apply   # one slice (substring match on the filename)
```

Expect explicit confirmation before Teardown cases. Do not wire this into CI that assumes a standing Applied Stack.

## Add a case (when implementing)

1. Add `lifecycle-test/NN-short-name.sh`.
2. Use observable outcomes (provider presence, Reserved IP value, volume marker bytes, SSH reachability) — not Terraform internals.
3. Document leftover Stack state in the case header (Parked vs Applied vs empty).
