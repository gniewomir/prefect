# Testing

How agents run and extend Propraetor’s executable checks. Glossary: **Acceptance Test**, **Lifecycle Test**, **Unit Test** in root `CONTEXT.md`. Decision: [ADR-0036](../adr/0036-unified-test-entrypoint.md). Argv grammar: [ADR-0039](../adr/0039-operator-cli-positionals-then-flags.md).

## Entrypoint

From the repo root:

```bash
./test.sh <suite> [<case-selector>] [--verbose] [--env <slug>]
./test.sh <suite> [--verbose] [--env <slug>]
```

- `<suite>` is **mandatory** — the name of a subdirectory of `internals/test/` (`acceptance`, `lifecycle`, or `unit`).
- `<case-selector>` is optional — unique substring of one case filename (Acceptance/Lifecycle) or of a Unit Test path/basename; multiple matches fail.
- Positionals come first; flags follow; flag order is free (ADR-0039).
- `--verbose` (or `TEST_VERBOSE=1`) streams each case live instead of quiet-on-pass buffering.
- `--env <slug>` is optional. Valid only for `acceptance` and `lifecycle` (ADR-0019 defaults). Passing `--env` to `unit` is invalid.
- Any other shape (missing suite, unknown suite, flag before positional, unknown flag) → print help and exit non-zero.

`./test.sh` is a thin dispatcher: it validates the suite directory, then execs `internals/test/<suite>/run.sh` with the remaining args.

By default, suite runners buffer each case’s stdout+stderr: they print `--- <name> ---` (and a spinner on a TTY) while the case runs, and dump the full log only when the case fails (`internals/test/run-buffered-case.sh`). With `--verbose` / `TEST_VERBOSE=1`, case output streams live. Setup / fixture output before the case loop always streams live.

## Suites

| Suite | Directory | What it checks |
|-------|-----------|----------------|
| `acceptance` | `internals/test/acceptance/` | Applied Stack external behavior; Host present; must not Park/Teardown |
| `lifecycle` | `internals/test/lifecycle/` | Park / Apply-after-Park / Teardown; opt-in; may leave Stack Parked or empty |
| `unit` | `internals/test/unit/` | Library/helper behavior; no Applied Stack required |

### Acceptance / Lifecycle cases

Numeric-prefixed `NN-short-name.sh` under the suite directory; runner builds fixture once (Acceptance) or runs destructive lifecycle cases (Lifecycle); fail-fast; filename sort is order. Shared helpers (`lib.sh`, fixtures) live in the suite directory.

### Unit Tests

Stay **colocated** next to the code they exercise as `*_test.sh`. The unit runner discovers all `internals/**/*_test.sh` via `find` (Acceptance/Lifecycle cases use `[0-9]*.sh`, so they are not included). No separate inventory file.

## Hard cut

No dual entrypoints (ADR-0018). Old `internals/acceptance-tests.sh` / `lifecycle-tests.sh` and the former top-level suite dirs are gone — use `./test.sh` only.
