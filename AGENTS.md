## Agent skills

### Issue tracker

GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles mapped 1:1 (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.

### Development posture

Pre-stability: no backwards compatibility by default (ADR-0018; always-apply rule `.cursor/rules/no-backwards-compat-in-development.mdc`).

## Cursor Cloud specific instructions

This repo is a Terraform + Bash infrastructure-as-code operator for DigitalOcean (see `README.md` / `CONTEXT.md`). There is no application server, database, or GUI — the deliverable is the Terraform Stack plus the operator shell scripts. Evidence of "running" is terminal output, not a web page.

Toolchain (provisioned in the VM snapshot): `terraform` (>= 1.5), `shellcheck`, `nc` (netcat-openbsd), plus `jq`/`curl`/`ssh`/`ping`/`tar`. The startup update script runs `terraform -chdir=terraform init` to fetch the pinned DigitalOcean provider.

What runs offline (no cloud, no credentials) — use these for local dev/CI:
- Unit/helper tests: `bash lib/environment_test.sh`, `bash lib/diagnostics_test.sh`.
- Invariant checks: `bash lib/check-cloud-init-ascii.sh`, `bash lib/check-stack-names.sh` (also auto-run inside `apply.sh` / `test.sh`).
- Lint: `terraform -chdir=terraform fmt -check -recursive`; `shellcheck` on `*.sh` (neither is wired as project tooling — `shellcheck` reports pre-existing style findings in sourced `lib.sh` files).
- Build/validate: `terraform -chdir=terraform validate`.
- Stack plan: the Stack has no `data` sources, so on an empty state `terraform -chdir=terraform plan` produces a full 11-resource create plan without any API calls. Provide a throwaway `DIGITALOCEAN_TOKEN=placeholder` and `TF_VAR_DIGITALOCEAN_PUBLIC_KEY="$(cat some_key.pub)"`; a real token is only needed for `apply`.

What requires live cloud (needs a real `DIGITALOCEAN_TOKEN` + `TF_VAR_DIGITALOCEAN_PUBLIC_KEY`, not present by default): `./apply.sh`, `./test.sh` (Acceptance Tests), `./lifecycle-test.sh` (destructive), `./ssh.sh`, `./diagnostics.sh`, and the `prefect/*.sh` host helpers. These SSH into a provisioned Host — they cannot be exercised offline.

Gotcha: the committed `terraform/.terraform.lock.hcl` only records the operator's platform hash, so `terraform init` on Linux appends a `linux_amd64` hash, leaving the lock file modified in the worktree. That change is expected — do not commit it unless intentionally maintaining multi-platform lock hashes.
