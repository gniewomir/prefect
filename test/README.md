# Acceptance Tests

Executable checks of Applied Stack external behavior. Requires an applied Stack and Credentials. Assert observable outcomes only — not Terraform internals.

## Run

From the repo root:

```bash
./test.sh              # all Acceptance Tests, numeric order, fail-fast
./test.sh 70-podman    # one slice (substring match on the filename)
```

Optional: `VERIFY_SSH_IDENTITY=/path/to/private_key` if the default SSH agent/identities are not enough.

## Add a new Acceptance Test

1. Pick the next free numeric prefix (gaps of 10 are intentional so you can insert).
2. Add `test/NN-short-name.sh` — one capability / contract slice per file.
3. Start from `set -euo pipefail`, source `lib.sh`, and use `pass` / `fail`.
4. Assume fixture env from the runner (`IP`, and when needed `STATE_JSON` / `HOST_JSON`). Do not re-run `terraform show` in the case.
5. Keep the script focused on external behavior. The runner discovers `test/[0-9]*.sh` automatically — no registry edit.

Non-case files in this directory (`lib.sh`, this README) are not executed.

## Layout

| Path | Role |
|------|------|
| `../test.sh` | Runner: tooling checks, fixture once, subprocess cases |
| `lib.sh` | Shared `pass` / `fail` / probes / SSH opts |
| `NN-*.sh` | Acceptance Tests (sort order = run order) |
