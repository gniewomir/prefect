# Acceptance Tests

Executable checks of Applied Stack external behavior. Requires an applied Stack and Credentials. Assert observable outcomes only — not Terraform internals.

**Entrypoint:** `./test.sh acceptance` — see [docs/agents/testing.md](../../../docs/agents/testing.md) (ADR-0036).

**Non-destructive:** Acceptance Tests must not Park or Teardown. They may mutate Host-local / Workload fixture state (Routes, certs, Purge) on a live Host, but they leave Stack lifecycle intact (Host and Durables remain). Stack lifecycle (Park, Apply-after-Park, Teardown) is covered by Lifecycle Tests — see `../lifecycle/README.md`.

## Run

From the repo root:

```bash
./test.sh acceptance                 # all Acceptance Tests on the test Environment (default)
./test.sh acceptance 70-podman       # one slice (substring match on the filename)
./test.sh acceptance --env test      # same Environment as omitting --env (`default` also aliases here)
./test.sh acceptance --env prod      # Acceptance against a non-test Applied Environment (explicit)
./test.sh acceptance 70-podman --env test
```

**Environment (ADR-0019):** every operator entrypoint is safe by default — no `--env` selects the **test** Environment (Terraform workspace `default`). `--env test` and `--env default` are the same alias; any other slug selects that Environment’s workspace. Targeting prod (or any non-test Environment) always requires an explicit `--env <slug>`. Positionals first, then flags; flag order free (ADR-0039).

Requires Provider Credential and Operator Configuration private key path (root `.env` or process environment — ADR-0038).

Fabric → Mirror → Orphan Reap → Components → Workloads → Purge (Deploy ladder to **Deployed**): the runner invokes `./internals/ensure.sh` (same Environment) before cases — ADR-0041; not Initial Host Provisioning and not Stack Apply. Operator root entrypoint for the same ladder is `./deploy.sh`.

## Add a new Acceptance Test

1. Pick the next free numeric prefix (gaps of 10 are intentional so you can insert).
2. Add `NN-short-name.sh` — one capability / contract slice per file.
3. Start from `set -euo pipefail`, source `lib.sh`, and use `pass` / `fail`.
4. Assume fixture env from the runner (`IP`, provider-observed `RESERVED_IP_JSON` / `HOST_JSON`) and use `do_api_get` for other provider outcomes.
5. Keep the script focused on external behavior. The runner discovers `[0-9]*.sh` automatically — no registry edit.
6. Do not call `./park.sh`, `./teardown.sh`, or otherwise remove the Host / Durables.

Non-case files in this directory (`lib.sh`, `run.sh`, this README) are not executed as cases.

## Layout

| Path | Role |
|------|------|
| `run.sh` | Suite runner (via `./test.sh acceptance`) |
| `lib.sh` | Shared `pass` / `fail` / probes / SSH opts |
| `NN-*.sh` | Acceptance Tests (sort order = run order) |
| `../lifecycle/` | Lifecycle Test suite |
| `../unit/` | Unit Test suite runner |
