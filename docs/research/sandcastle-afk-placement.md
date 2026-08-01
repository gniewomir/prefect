# Sandcastle placement: separate AFK orchestrator vs per-project embed

**Researched:** 2026-08-01  
**Question:** Should [mattpocock/sandcastle](https://github.com/mattpocock/sandcastle) be a **separate project** that drives AFK (away-from-keyboard / unattended agent) work across repos, or should it be **configured/embedded per project** (e.g. inside each application repo like `infra`)?  
**Scope:** Sandcastle as published on GitHub (`mattpocock/sandcastle`, default branch `main` as of research) and npm (`@ai-hero/sandcastle@0.12.0`). Compared against this repo’s existing AFK stack (GitHub Issues triage, agent skills, Cursor CLI/SDK automation research). Primary sources only: Sandcastle README, `CONTEXT.md`, ADRs, package/source, in-repo docs site MDX, `.out-of-scope/` notes, and this repo’s agent docs / prior Cursor research.  
**Method:** Claims cite first-party Sandcastle or `infra` docs. Claims marked **Inference** combine multiple primary statements. An absence claim means the documented/source surface does not state it; it is not a promise about undocumented internals. The uploaded scrape at `uploads/sandcastle-0.md` was treated as a hint only; live GitHub raw / API and the extracted `main` tarball were authoritative.

---

## Verdict

1. **Default placement matches the author’s design: embed per host repo.** `sandcastle init` scaffolds a `.sandcastle/` **config directory in a host repo**; templates, Dockerfile/Containerfile, prompts, `.env`, worktrees, and logs live there. The documented quick start is `npm install --save-dev @ai-hero/sandcastle` then `npx @ai-hero/sandcastle init` **in your repository**, then `npx tsx .sandcastle/main.ts` ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md), [docs index](https://github.com/mattpocock/sandcastle/blob/main/docs/content/docs/index.mdx), [`CONTEXT.md` Init / Config directory](https://github.com/mattpocock/sandcastle/blob/main/CONTEXT.md)).
2. **A separate cross-repo orchestrator project is a supported *caller* pattern, not a replacement for per-repo config.** ADR-0002 added `cwd` so “callers orchestrating multiple repos from a single Node process” can target another repo without `chdir`. Host-repo artifacts (`.sandcastle/worktrees/`, `.sandcastle/.env`, logs, patches) still follow that `cwd` ([ADR-0002](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0002-cwd-option.md), [README `cwd` option](https://github.com/mattpocock/sandcastle/blob/main/README.md)).
3. **One sandbox session still assumes one primary git repo** for worktrees, branches, and commit extraction. Multi-repo *inside* one sandbox is explicitly out of scope; secondary repos can only be bind-mounted without Sandcastle branch/commit management ([`.out-of-scope/multi-repo-sandbox.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/multi-repo-sandbox.md)).
4. **For `infra` today (single AFK codebase with existing triage/skills):** prefer **per-project embed** (`.sandcastle/` in `infra`), and treat Sandcastle as an **orchestration/runtime layer above** Cursor CLI/SDK, GitHub Issues, and `.agents/skills/` — not as a replacement for them. A separate orchestrator repo only becomes justified when you need one Node process to fan out `run({ cwd })` across many checkouts that each still carry their own `.sandcastle/`.

---

## 1. What Sandcastle is

### Purpose

Sandcastle is a TypeScript **library + CLI** for orchestrating AI coding agents in isolated sandboxes. The product framing is:

1. Invoke agents with `sandcastle.run()` (exported as `run`).
2. Sandcastle sandboxes the agent with a configurable **branch strategy**.
3. Commits on those branches are merged back (per strategy).

It is marketed for “parallelizing multiple AFK agents, creating review pipelines, or even just orchestrating your own agents,” and is **provider-agnostic** for sandboxes ([README — What Is Sandcastle?](https://github.com/mattpocock/sandcastle/blob/main/README.md); [`CONTEXT.md`](https://github.com/mattpocock/sandcastle/blob/main/CONTEXT.md)).

The published npm package is **`@ai-hero/sandcastle`** (latest researched: `0.12.0`). The unscoped npm name `sandcastle` is an unrelated 2015 JavaScript sandbox by another author — do not confuse them ([npm `@ai-hero/sandcastle`](https://www.npmjs.com/package/@ai-hero/sandcastle), [npm `sandcastle`](https://www.npmjs.com/package/sandcastle)).

### API surface

Primary programmatic APIs (README / package exports):

| API | Role |
| --- | --- |
| `run(options)` | One-shot: create sandbox, run agent iterations, collect commits, tear down |
| `createSandbox(options)` | Long-lived sandbox; multiple `sandbox.run()` / `interactive()` / `exec()` |
| `createWorktree(options)` | Independent worktree lifecycle; then `wt.run()` / `wt.interactive()` / `wt.createSandbox()` |
| `interactive(options)` | Interactive agent session (can use `noSandbox()`) |
| Agent factories | `claudeCode`, `codex`, `pi`, `cursor`, `opencode`, `copilot` (built-ins; curated list) |
| Sandbox factories | `docker`, `podman`, `vercel`, `daytona`, `noSandbox` (+ custom via `createBindMountSandboxProvider` / `createIsolatedSandboxProvider`) |

([README API](https://github.com/mattpocock/sandcastle/blob/main/README.md), [`package.json` exports](https://github.com/mattpocock/sandcastle/blob/main/package.json), [`src/AgentProvider.ts`](https://github.com/mattpocock/sandcastle/blob/main/src/AgentProvider.ts)).

CLI commands focus on **scaffold and image lifecycle**, not a long-running multi-repo service: `sandcastle init`, `sandcastle docker|podman build-image`, `sandcastle docker|podman remove-image` ([README — CLI commands](https://github.com/mattpocock/sandcastle/blob/main/README.md)).

### Runtime model (local vs cloud)

| Provider | Type | Notes |
| --- | --- | --- |
| Docker / Podman | Bind-mount | Host worktree/repo mounted into container; default branch strategy `head` for bind-mount |
| Vercel / Daytona | Isolated | Own filesystem; sync in/out; default `merge-to-head` for isolated |
| `noSandbox()` | None | Agent on host; accepted by `run` / `createSandbox` / `interactive` |

([README — Sandbox Providers / How it works](https://github.com/mattpocock/sandcastle/blob/main/README.md), [`.out-of-scope/built-in-sandbox-providers.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/built-in-sandbox-providers.md)).

### Relation to Claude Code / Cursor / other agents

Sandcastle does **not** replace the agent product. It **shells out** to agent CLIs inside the sandbox. Built-in agent providers include Claude Code (default in docs/examples), Codex, Pi, **Cursor** (`agent --print --output-format stream-json …`), OpenCode, and GitHub Copilot CLI ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md), [`cursor()` in `AgentProvider.ts`](https://github.com/mattpocock/sandcastle/blob/main/src/AgentProvider.ts), [`.out-of-scope/built-in-agent-providers.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/built-in-agent-providers.md)).

Cursor-as-provider is non-resumable in Sandcastle (`captureSessions: false`; no filesystem-backed session storage) ([`cursor()` comments / ADR references in source](https://github.com/mattpocock/sandcastle/blob/main/src/AgentProvider.ts)).

Issue tracking is also **not embedded at runtime**: init substitutes shell commands (`LIST_TASKS_COMMAND`, etc.) into prompts; the agent/`gh` CLI runs them ([`docs/agents/adding-an-issue-tracker.md`](https://github.com/mattpocock/sandcastle/blob/main/docs/agents/adding-an-issue-tracker.md)).

---

## 2. How it is meant to be used

### Library you import into a per-repo script

Authoritative usage path:

```bash
npm install --save-dev @ai-hero/sandcastle
npx @ai-hero/sandcastle init
npx tsx .sandcastle/main.ts
```

Templates scaffold `main.ts` / `main.mts` under `.sandcastle/` that call `run()` (or multi-phase `run()` loops). Templates are copied **verbatim** into the user’s `.sandcastle/` and may only depend on the published package, not Sandcastle internals ([README Quick start / Templates](https://github.com/mattpocock/sandcastle/blob/main/README.md), [ADR-0009](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0009-templates-no-shared-code.md), [simple-loop `main.mts`](https://github.com/mattpocock/sandcastle/blob/main/src/templates/simple-loop/main.mts)).

### CLI

The CLI is for **init and image build/remove**, not a daemon that watches many repos. Orchestration loops live in user TypeScript (`main.mts`, CI scripts, custom tooling) ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md)).

### Multi-repo vs single-repo

- **Happy path:** one host git repo ↔ one `.sandcastle/` ↔ `run()` with default `cwd = process.cwd()`.
- **Multi-repo caller:** pass `cwd: "../other-repo"` (or absolute path) on `run` / `interactive` / `createSandbox` / `createWorktree`. Relative `cwd` resolves against `process.cwd()`. `promptFile` still resolves against **`process.cwd()`, not `cwd`** ([ADR-0002](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0002-cwd-option.md), [README](https://github.com/mattpocock/sandcastle/blob/main/README.md)).
- **Not supported:** one sandbox owning N independent repos’ worktrees/branches/commits ([`.out-of-scope/multi-repo-sandbox.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/multi-repo-sandbox.md)).

**Inference:** Sandcastle is designed as a **per-host-repo runtime library**. Cross-repo AFK is “your Node script calls `run({ cwd })` N times,” not “Sandcastle is the monorepo/orchestrator product.”

### Workflow templates (in-repo orchestration shapes)

Init templates demonstrate **single-repo** orchestration sophistication (loops, parallel branches, review), not a separate service:

| Template | Shape |
| --- | --- |
| `blank` | Bare scaffold |
| `simple-loop` | Pick issues one-by-one |
| `sequential-reviewer` | Implement then review |
| `parallel-planner` | Plan → parallel branch executes → merge |
| `parallel-planner-with-review` | Same + per-branch review |

([README Templates](https://github.com/mattpocock/sandcastle/blob/main/README.md), [parallel-planner `main.mts`](https://github.com/mattpocock/sandcastle/blob/main/src/templates/parallel-planner/main.mts)).

---

## 3. Configuration surface (project-local vs global)

### Project-local (host repo `.sandcastle/`)

`CONTEXT.md` defines **Config directory** as “The `.sandcastle/` directory in a **host** repo containing sandbox configuration.” Init creates it and errors if it already exists ([`CONTEXT.md`](https://github.com/mattpocock/sandcastle/blob/main/CONTEXT.md), [README Configuration](https://github.com/mattpocock/sandcastle/blob/main/README.md)).

Typical contents after init (README + `InitService`):

- `Dockerfile` or `Containerfile` (sandbox image; user-owned after scaffold)
- `prompt.md` (and template-specific prompts)
- `main.ts` / `main.mts` (orchestration script)
- `.env.example` / `.env` (tokens; gitignored)
- `.gitignore` ignoring `.env`, `logs/`, `worktrees/`
- Runtime artifacts: `logs/`, `worktrees/`, patches (under `.sandcastle/`)

Env resolution in source: **`.sandcastle/.env` keys**, with empty values falling back to `process.env`. Repo-root `.env` is **not** in this chain ([`EnvResolver.ts`](https://github.com/mattpocock/sandcastle/blob/main/src/EnvResolver.ts)).

> **Docs-site caveat:** in-repo MDX [`docs/content/docs/configuration.mdx`](https://github.com/mattpocock/sandcastle/blob/main/docs/content/docs/configuration.mdx) mentions `config.json` and “Repository root `.env`” in the resolution order. Init tests assert the blank template **does not** scaffold `config.json`, and `EnvResolver` does not read repo-root `.env`. Prefer README + source for config layout; treat that MDX as potentially stale.

### What is *not* owned by Sandcastle’s config dir

- **Agent product skills / rules** (e.g. Claude/Cursor project skills under `.agents/`, `.cursor/`, etc.) live in the **target repo / agent tooling**, not as a Sandcastle config type. Sandcastle’s own out-of-scope note rejects shipping large third-party skill trees as built-in templates ([`.out-of-scope/bundled-workflow-templates.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/bundled-workflow-templates.md)).
- **Issue tracker integration** is scaffold-time command substitution into prompts, not a Sandcastle service ([`adding-an-issue-tracker.md`](https://github.com/mattpocock/sandcastle/blob/main/docs/agents/adding-an-issue-tracker.md)).
- **Namespace / `.sandcastle` prefix** is not configurable; isolation between projects is “separate host repo directories” ([`.out-of-scope/configurable-namespace-prefix.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/configurable-namespace-prefix.md)).

### Credentials

Agent/sandbox credentials (e.g. `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY`, `GH_TOKEN` for Claude Code + GitHub) are documented as `.sandcastle/.env` (and provider `env` overrides). Sessions for resumable agents are captured to **host** agent home dirs (`~/.claude/…`, `~/.codex/…`, `~/.pi/…`) ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md), [agents MDX](https://github.com/mattpocock/sandcastle/blob/main/docs/content/docs/agents.mdx)).

### Author intent on placement

Stated intent from first-party material:

- Init scaffolds **in a new/host repo**; “All per-repo sandbox configuration lives in `.sandcastle/`” ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md)).
- Dockerfile control is inverted to the user after scaffold ([`.out-of-scope/custom-base-image-abstraction.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/custom-base-image-abstraction.md)).
- `cwd` exists specifically for multi-repo **callers** ([ADR-0002](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0002-cwd-option.md)).
- Multi-repo **inside** one sandbox is deferred / out of scope ([`.out-of-scope/multi-repo-sandbox.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/multi-repo-sandbox.md)).

No first-party README/ADR statement recommends a standalone “AFK control plane” repo as the primary product shape.

---

## 4. Comparison to this repo’s existing AFK stack (`infra`)

Sources for `infra`: [issue tracker](../agents/issue-tracker.md), [triage labels](../agents/triage-labels.md), [Cursor agents/CLI research](cursor-agents-cli-automation.md), plus workspace skills under `.agents/skills/` and Cursor Automations/Autopilot at `~/.cursor/skills-cursor/`.

| Concern | `infra` today | Sandcastle | Fit |
| --- | --- | --- | --- |
| Work queue | GitHub Issues + triage roles; AFK gate = `ready-for-agent` | Templates default GitHub filter label **`Sandcastle`** (`LIST_TASKS_COMMAND` in `InitService`); custom tracker / prompt edit supported | Overlap possible; labels must be aligned deliberately |
| Agent brief / skills | `.agents/skills/`, `docs/agents/*`, `AGENTS.md` | Prompt files under `.sandcastle/`; no built-in skill pack | **Complementary** — skills stay in repo; Sandcastle feeds prompts |
| Unattended execution | Cursor CLI headless / SDK / Cloud Agents (see prior research) | Sandbox + `run()` loop; can drive `cursor()` CLI or Claude Code / others | **Complementary / alternative runtime** — Sandcastle can wrap Cursor CLI *or* other agents |
| Isolation | Cursor Cloud Agents / sandbox policies (Cursor docs) | Docker/Podman/Vercel/Daytona/`noSandbox` | Different product; Sandcastle owns container/VM lifecycle for its providers |
| Branch / PR hygiene | Operator / Autopilot skills | First-class branch strategies + worktrees under `.sandcastle/worktrees/` | Sandcastle strength if you want local AFK with merge/branch automation |
| Multi-repo AFK | Not a first-class `infra` product | `cwd` for multi-repo callers; not multi-repo-in-one-sandbox | Orchestrator repo only if you outgrow one host repo |

**Inference:** Sandcastle does **not** replace triage labels, issue briefs, or Cursor Automations/Autopilot. It is a **harness**: sandbox lifecycle, iterations, completion signals, structured output, and branch strategies around whatever agent CLI and prompt/issue commands you configure. Sitting **above** the existing stack (embed `.sandcastle/` in `infra`, point prompts at `ready-for-agent` via custom/`--issue-tracker custom` or edited commands) matches both designs better than treating Sandcastle as a separate org-wide AFK service that absorbs skills and labels.

---

## 5. Recommendation

### Answer in one line

**Configure/embed Sandcastle per application repo; use a separate orchestrator project only as a thin multi-`cwd` caller if/when you drive many repos — never as a substitute for each target’s `.sandcastle/`.**

### Rationale tied to design

1. Sandcastle **is** a per-host-repo TypeScript dependency + `.sandcastle/` config directory ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md), [`CONTEXT.md`](https://github.com/mattpocock/sandcastle/blob/main/CONTEXT.md)).
2. Cross-repo orchestration is already modeled as **`cwd` on the library API**, not as a separate product ([ADR-0002](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0002-cwd-option.md)).
3. Putting *only* an orchestrator repo with **no** `.sandcastle/` in targets fights artifact placement (worktrees, env, logs, Dockerfile image build) which anchors under the host repo’s `.sandcastle/` ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md), [ADR-0002](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0002-cwd-option.md)).
4. For **`infra` alone**, a separate project adds indirection without multi-repo benefit; embed and wire prompts to existing `ready-for-agent` / skills.

### Practical shapes

| Shape | When |
| --- | --- |
| **A. Per-project embed** (recommended default) | One primary AFK repo (`infra`). `sandcastle init` here; customize prompts/labels; run `npx tsx .sandcastle/main.ts` or CI. |
| **B. Hybrid** | Many sibling repos. Each has `.sandcastle/` (image, env, worktrees). Optional thin `afk-orchestrator` repo/scripts call `run({ cwd: "…" })` with absolute `promptFile`s as ADR-0002 requires. |
| **C. Separate-only (avoid)** | One orchestrator, zero per-repo config — fights Sandcastle’s host-repo config model and out-of-scope multi-repo-in-sandbox. |

---

## 6. Open questions / risks

1. **Label vocabulary mismatch:** default scaffold filters `--label Sandcastle`; `infra` uses `ready-for-agent`. Must customize at init (`custom` tracker or edit prompts / decline create-label and rewrite commands) ([`InitService` GitHub entry](https://github.com/mattpocock/sandcastle/blob/main/src/InitService.ts), [`triage-labels.md`](../agents/triage-labels.md)).
2. **Agent choice vs existing Cursor investment:** Sandcastle’s happiest path in docs is Claude Code + Docker; Cursor provider exists but is non-resumable. Dual stacks (Cursor Automations + Sandcastle+Claude) may duplicate spend/process ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md), [`AgentProvider.ts` `cursor`](https://github.com/mattpocock/sandcastle/blob/main/src/AgentProvider.ts), [cursor-agents-cli-automation.md](cursor-agents-cli-automation.md)).
3. **Docs-site vs source drift:** `configuration.mdx` (`config.json`, root `.env`) may mislead operators; verify against `EnvResolver` / init behavior before relying on it.
4. **npm version vs README on GitHub:** researched npm latest was `0.12.0` while README documents features (Daytona export, fork API, etc.) present in the `main` tree — pin and verify the installed version against the README revision you follow.
5. **Multi-repo-in-sandbox** remains out of scope if a future Prefect/app workflow needs one agent touching N git roots with branch management ([`.out-of-scope/multi-repo-sandbox.md`](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/multi-repo-sandbox.md)).
6. **Permissions / unattended risk:** AFK runs typically use dangerous-skip / force-style flags inside sandboxes; isolation quality depends on provider choice (`noSandbox()` removes container isolation) ([README](https://github.com/mattpocock/sandcastle/blob/main/README.md)).

---

## Sources

### Sandcastle (primary)

- [GitHub: mattpocock/sandcastle](https://github.com/mattpocock/sandcastle)
- [README.md](https://github.com/mattpocock/sandcastle/blob/main/README.md) (fetched via raw + tarball `main`)
- [CONTEXT.md](https://github.com/mattpocock/sandcastle/blob/main/CONTEXT.md)
- [package.json](https://github.com/mattpocock/sandcastle/blob/main/package.json) / [npm `@ai-hero/sandcastle`](https://www.npmjs.com/package/@ai-hero/sandcastle)
- [ADR-0002 `cwd` option](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0002-cwd-option.md)
- [ADR-0009 templates no shared code](https://github.com/mattpocock/sandcastle/blob/main/docs/adr/0009-templates-no-shared-code.md)
- [docs/content/docs/index.mdx](https://github.com/mattpocock/sandcastle/blob/main/docs/content/docs/index.mdx)
- [docs/content/docs/configuration.mdx](https://github.com/mattpocock/sandcastle/blob/main/docs/content/docs/configuration.mdx)
- [docs/content/docs/agents.mdx](https://github.com/mattpocock/sandcastle/blob/main/docs/content/docs/agents.mdx)
- [docs/agents/adding-an-issue-tracker.md](https://github.com/mattpocock/sandcastle/blob/main/docs/agents/adding-an-issue-tracker.md)
- [docs/agents/triage.md](https://github.com/mattpocock/sandcastle/blob/main/docs/agents/triage.md)
- [src/EnvResolver.ts](https://github.com/mattpocock/sandcastle/blob/main/src/EnvResolver.ts)
- [src/resolveCwd.ts](https://github.com/mattpocock/sandcastle/blob/main/src/resolveCwd.ts)
- [src/AgentProvider.ts](https://github.com/mattpocock/sandcastle/blob/main/src/AgentProvider.ts) (`cursor`, `claudeCode`, …)
- [src/InitService.ts](https://github.com/mattpocock/sandcastle/blob/main/src/InitService.ts) (issue-tracker commands / label `Sandcastle`)
- [src/templates/simple-loop/](https://github.com/mattpocock/sandcastle/tree/main/src/templates/simple-loop), [parallel-planner/](https://github.com/mattpocock/sandcastle/tree/main/src/templates/parallel-planner)
- [.out-of-scope/multi-repo-sandbox.md](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/multi-repo-sandbox.md)
- [.out-of-scope/configurable-namespace-prefix.md](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/configurable-namespace-prefix.md)
- [.out-of-scope/bundled-workflow-templates.md](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/bundled-workflow-templates.md)
- [.out-of-scope/built-in-agent-providers.md](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/built-in-agent-providers.md)
- [.out-of-scope/built-in-sandbox-providers.md](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/built-in-sandbox-providers.md)
- [.out-of-scope/custom-base-image-abstraction.md](https://github.com/mattpocock/sandcastle/blob/main/.out-of-scope/custom-base-image-abstraction.md)

### This repo / prior research

- [docs/agents/issue-tracker.md](../agents/issue-tracker.md)
- [docs/agents/triage-labels.md](../agents/triage-labels.md)
- [docs/research/cursor-agents-cli-automation.md](cursor-agents-cli-automation.md)

### Explicitly not authoritative alone

- Uploaded scrape `uploads/sandcastle-0.md` (verified against live GitHub/npm; not cited as a claim source)
- Unscoped npm package [`sandcastle`](https://www.npmjs.com/package/sandcastle) (different project)
