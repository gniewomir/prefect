# Testing

How agents run and extend Propraetor’s executable checks. Glossary: **Acceptance Test**, **Lifecycle Test**, **Unit Test** in root `CONTEXT.md`. Decisions: [ADR-0036](../adr/0036-unified-test-entrypoint.md) (entrypoint), [ADR-0042](../adr/0042-suite-baselines-and-test-isolation.md) (suite baselines / isolation). Argv grammar: [ADR-0039](../adr/0039-operator-cli-positionals-then-flags.md).

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
- `--env <slug>` is optional. Valid for `acceptance` (ADR-0019; non-**test** requires typed `diagnose <slug>` — ADR-0042). Valid for `lifecycle` only as **test** / `default` (any other slug fail closed — ADR-0042). Passing `--env` to `unit` is invalid.
- Any other shape (missing suite, unknown suite, flag before positional, unknown flag) → print help and exit non-zero.

`./test.sh` is a thin dispatcher: it validates the suite directory, then execs `internals/test/<suite>/run.sh` with the remaining args.

By default, suite runners buffer each case’s stdout+stderr: they print `--- <name> ---` (and a spinner on a TTY) while the case runs, and dump the full log only when the case fails (`internals/test/run-buffered-case.sh`). With `--verbose` / `TEST_VERBOSE=1`, case output streams live. Setup / fixture output before the case loop always streams live.

## Suites

| Suite | Directory | What it checks | Suite baseline (ADR-0042) |
|-------|-----------|----------------|---------------------------|
| `acceptance` | `internals/test/acceptance/` | Deployed Host external behavior; must not Park/Teardown | **Deployed** — runner **Deploy** before each case |
| `lifecycle` | `internals/test/lifecycle/` | Park / Apply-after-Park / Teardown; opt-in; **test** only | Stack **absent** — runner **Teardown** before each case |
| `unit` | `internals/test/unit/` | Library/helper behavior; no Applied Stack; no lasting side effects outside test temp workspace | None |

Peer-pollution cleanup is banned. Full policy: ADR-0042 / issue #159.

### Acceptance / Lifecycle cases

Numeric-prefixed `NN-short-name.sh` under the suite directory; fail-fast; filename sort is order. Shared helpers (`lib.sh`, fixtures) live in the suite directory. Acceptance: cases restore Environment SoT before exit; runner Deploy restores Host. Lifecycle: cases Apply when they need a Stack; runner Teardown baselines between cases.

### Unit Tests

Stay **colocated** next to the code they exercise as `*_test.sh`. The unit runner discovers all `internals/**/*_test.sh` via `find` (Acceptance/Lifecycle cases use `[0-9]*.sh`, so they are not included). No separate inventory file. Lasting side effects ⇒ not a Unit Test (ADR-0042).

## Hard cut

No dual entrypoints (ADR-0018). Old `internals/acceptance-tests.sh` / `lifecycle-tests.sh` and the former top-level suite dirs are gone — use `./test.sh` only.
