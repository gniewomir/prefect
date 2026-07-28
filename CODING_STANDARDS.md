# Coding standards

How code in this repo should be written. `/code-review` treats this file as a standards source; skip anything tooling already enforces.

Background research for the portability rules: `docs/research/shell-linux-macos-portability.md`.

## Shell

- **Dialect:** Bash. Executables use `#!/usr/bin/env bash` and `set -euo pipefail` (sourced libraries inherit the caller's `set`). Do not switch shared scripts to POSIX `sh` for portability theater.
- **Lint:** ShellCheck is authoritative for SC* findings. Run `./lint-shell.sh` (optional paths as args). Config: `.shellcheckrc`.
- **Baseline disables** in `.shellcheckrc` are intentional (e.g. client-side expansion into SSH/heredoc payloads). Do not re-litigate them in review.
- **One-off exceptions:** `# shellcheck disable=SC####  # why` next to the site — prefer that over widening the repo baseline.
- **Optional checks** (`shellcheck --enable=all`) are not part of the gate; do not enable them in `.shellcheckrc` without revisiting the baseline.

### Linux + macOS portability

Shared Bash scripts must run on Ubuntu Host **and** macOS operator machines unless a path is explicitly Host-only or operator-only.

ShellCheck (`shell=bash`) does **not** enforce this section — reviewers and authors must. It will not catch Bash 4+ features or GNU-only utility flags.

**Bash floor: stock macOS 3.2.** Assume `#!/usr/bin/env bash` may resolve to `/bin/bash` 3.2.57 on macOS. Do not use Bash 4+ features in shared scripts, including: `declare -A`, `mapfile`/`readarray`, `globstar` (`**`), `|&` / `&>>`, case `;&` / `;;&`, `${var,,}` / `${var^^}`, `declare -n` namerefs, `EPOCHSECONDS` / `EPOCHREALTIME`. Arrays, `[[ ]]`, `$(( ))`, process substitution, `pipefail`, and `local` are fine.

**Prefer `printf` over `echo`** when flags or escapes matter (`echo -n` / `echo -e` are not portable).

**Forbidden GNU-only (or GNU/BSD-divergent) patterns** in shared scripts — use the portable alternative:

| Avoid | Prefer |
| --- | --- |
| `sed -i` (GNU vs `sed -i ''` on macOS) | Temp file + `mv`, or OS-branched in-place only if unavoidable |
| `date -d` / `date --date` | `date +FMT` / `date +%s`; date math in Bash or a small helper |
| `grep -P` | `grep -E` / `-F`, `sed`, or `awk` |
| `find -printf` | `-print` / `-print0`, or `-exec` |
| `stat -c '…'` (GNU) | Avoid formatted `stat`; or OS-specific paths only |
| `readlink -f` as “always works” | `realpath` when available, or avoid; do not build critical logic on `$0` / `readlink -f "$0"` ([BashFAQ/028](https://mywiki.wooledge.org/BashFAQ/028)) |
| `cp -r` as the documented recursive flag | `cp -R` |
| Locale-sensitive `sort` / `[A-Z]` ranges for machine parsing | `LC_ALL=C` |

**Temp files:** `mktemp` / `mktemp -d` with an explicit `XXXXXX` template under `"${TMPDIR:-/tmp}"` (e.g. `mktemp -d "${TMPDIR:-/tmp}/foo.XXXXXX"`); `umask 077` when creating dirs.

**NUL-safe file lists:** `find … -print0` with `read -d ''` or `xargs -0` when names may contain spaces/newlines.

## Terraform

Stack HCL lives under `terraform/`. Formatting and lint are gated; lifecycle/domain rules are not.

- **Format:** Canonical `terraform fmt` style. The gate is `terraform fmt -check -recursive`.
- **Validate:** `terraform validate` after `terraform init -backend=false` (no cloud backend / credentials required for the gate).
- **Lint:** TFLint with the `terraform` plugin `recommended` preset is authoritative for TFLint findings. Run `./lint-terraform.sh`. Config: `terraform/.tflint.hcl`.
- **Baseline disables** in `.tflint.hcl` are intentional (version pins live at Stack root). Do not re-litigate them in review.
- **One-off exceptions:** `# tflint-ignore: rule_name  # why` next to the site — prefer that over widening the repo baseline.
- **Security / policy scanners** (Checkov, Trivy, tfsec) are not part of the gate.

### Lifecycle and ownership (human)

TFLint does **not** enforce Durable/Recreatable placement, `prevent_destroy`, membership ownership, or Apply/Park convergence. Those follow ADR-0025, `CONTEXT.md`, and `.cursor/rules/terraform-lifecycle-convergence.mdc` — reviewers and authors must.