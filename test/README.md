# Acceptance Tests

Executable checks of Applied Stack external behavior. Requires an applied Stack and Credentials. Assert observable outcomes only — not Terraform internals.

**Non-destructive:** Acceptance Tests must not Park or Teardown. They may mutate Host-local / Workload fixture state (Routes, certs, Purge) on a live Host, but they leave Stack lifecycle intact (Host and Durables remain). Stack lifecycle (Park, Apply-after-Park, Teardown) is covered by Lifecycle Tests — see `../lifecycle-test/README.md` and `../lifecycle-test.sh`.

## Run

From the repo root:

```bash
./test.sh              # all Acceptance Tests, numeric order, fail-fast
./test.sh 70-podman    # one slice (substring match on the filename)
```

Optional: `VERIFY_SSH_IDENTITY=/path/to/private_key` if the default SSH agent/identities are not enough.

Components (empty Edge → HTTP 404 on :80): the runner invokes `./prefect/ensure-components.sh` before cases (idempotent Component Setup on the Host Volume; not Initial Host Provisioning).

## Add a new Acceptance Test

1. Pick the next free numeric prefix (gaps of 10 are intentional so you can insert).
2. Add `test/NN-short-name.sh` — one capability / contract slice per file.
3. Start from `set -euo pipefail`, source `lib.sh`, and use `pass` / `fail`.
4. Assume fixture env from the runner (`IP`, and when needed `STATE_JSON` / `HOST_JSON`). Do not re-run `terraform show` in the case.
5. Keep the script focused on external behavior. The runner discovers `test/[0-9]*.sh` automatically — no registry edit.
6. Do not call `park.sh`, `teardown.sh`, or otherwise remove the Host / Durables.

Non-case files in this directory (`lib.sh`, this README) are not executed.

## Layout

| Path | Role |
|------|------|
| `../test.sh` | Runner: tooling checks, fixture once, subprocess cases |
| `lib.sh` | Shared `pass` / `fail` / probes / SSH opts |
| `NN-*.sh` | Acceptance Tests (sort order = run order) |
| `../lifecycle-test.sh` | Lifecycle Test runner (destructive; opt-in) |
| `../lifecycle-test/` | Lifecycle Test cases |
