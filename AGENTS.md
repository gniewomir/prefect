## Agent skills

### Issue tracker

GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles mapped 1:1 (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.

### Development posture

Pre-stability: no backwards compatibility by default (ADR-0018; always-apply rule `.cursor/rules/no-backwards-compat-in-development.mdc`).

### Coding standards

See root `CODING_STANDARDS.md` (ShellCheck and related conventions).
