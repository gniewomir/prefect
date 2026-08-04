# Security-review agent skills and playbooks

**Researched:** 2026-08-04  
**Question:** What credible, publicly available agent skills / playbooks / prompt packs exist for security code review (especially AI-assisted PR/diff security review) that we can use as inspiration for designing our own security-review skill?  
**Scope:** Open skills ecosystem (skills.sh / GitHub Agent Skills / Claude/Cursor skills); security-review methodologies from credible security orgs that could be embodied as a skill; AI-for-secure-development guidance from credible vendors/labs that ships as skill-like artifacts or clear review checklists/workflows. Prefer artifacts that are actionable as a skill (ordered process, completion criteria, severity taxonomy, finding format). Out of scope: writing our skill; deep review of Cursor’s built-in `security-review` subagent internals beyond noting it as a baseline; marketing fluff without primary artifacts.  
**Method:** Primary sources only. Rubric A/B/C applied to every candidate (documented below). Channels searched: [skills.sh](https://skills.sh/) leaderboard plus `npx skills find` for security / code review / appsec / owasp / audit / sast / secrets; GitHub `SKILL.md` + security-review artifacts from known orgs; OWASP ASVS / Code Review Guide / Cheat Sheet Series; Anthropic, OpenAI, GitHub, Microsoft, Cursor published guidance; Trail of Bits, Semgrep, Snyk, NCC Group public methodologies where skill-like or checklist artifacts exist. Claims cite owning URLs; inferences are labeled.

---

## Assessment methodology

Every candidate is scored on three axes. Scores are **High / Medium / Low / Fail**, with evidence.

### A. Source credibility (gate)

**Fail excludes** the candidate from “recommended inspiration.”

Score **High** only if at least one of:

1. **Security credibility:** OWASP, CISA, NIST, CERT/SEI, major cloud security teams (Google/Microsoft/AWS security), established AppSec vendors with published methodology (Snyk, Trail of Bits, NCC Group, Semgrep, GitHub Security), academic security labs with peer-reviewed or widely cited work.
2. **AI-in-SDLC credibility:** Anthropic, OpenAI, Google DeepMind/Google Labs, Microsoft (GitHub Copilot / Azure AI), Cursor, Meta (Llama/CodeLlama security work), major platform engineering orgs known for agent tooling (Vercel Labs is weaker for *security* specifically — note that).

**Both** dimensions → flag as **Gold**.

**Fail:** anonymous gist, unknown author with ≪100 stars and no institutional affiliation, SEO blog farms, “awesome list” aggregations that do not point at primary artifacts.

### B. Artifact quality (skill inspiration)

1. Process shape — ordered steps / workflow vs freeform advice  
2. Completion criteria — how the reviewer knows they are done  
3. Threat/finding taxonomy — OWASP Top 10, CWE, STRIDE, custom severity, etc.  
4. Diff/PR scoping — change review vs whole-codebase audit  
5. False-positive / confidence discipline — verified findings vs laundry lists  
6. Output contract — structured finding format agents can reliably produce  
7. Tool/legwork expectations — SAST, secret scanning, dependency review, manual reasoning  
8. Progressive disclosure — checklists/reference separated from core steps  

### C. Applicability to our context

Fit for a **pre-stability infra/shell/Terraform** repo (not a typical web app): secrets, supply chain, IAM, container/host isolation, CI, shell injection — and how much of the candidate is web/AppSec-skewed.

**Inventory labels:** Gold / Recommended / Interesting / Discard.

---

## Verdict

1. **Best skill-shaped inspiration for PR/diff security review is Trail of Bits `differential-review`** ([skill](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md), [product page](https://trailofbits.com/skills/differential-review/)): ordered phases, risk triage, blast radius, git-history regression checks, adversarial modeling, completion checklist, and a mandatory report contract. Red Hat Product Security redistributes an adapted copy ([prodsec-skills](https://github.com/RedHatProductSecurity/prodsec-skills)). **Gold.**
2. **Best “high-signal, low-noise” AI review prompt packs are Anthropic’s `/security-review` command** ([prompt](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md)) **and Cursor’s published Automations “Find vulnerabilities” template** ([workflow](https://cursor.com/workflows/autonomous-agents/find-vulnerabilities), [blog](https://cursor.com/blog/security-agents)). Both converge on: scope to the diff, demand attacker-controlled input → sink, filter hard, report only medium+ with concrete evidence. **Gold.**
3. **Best progressive-disclosure reference pack for AppSec + some infra is Sentry’s `security-review` skill** ([SKILL.md](https://github.com/getsentry/skills/blob/main/skills/security-review/SKILL.md)); their companion **`gha-security-review`** is unusually strong for CI threat models we care about ([skill](https://github.com/getsentry/skills/blob/main/skills/gha-security-review/SKILL.md)). **Gold / Recommended.**
4. **Methodology substrate (not a skill, but steal the shapes):** OWASP [Secure Code Review Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Code_Review_Cheat_Sheet.html) (diff-based vs baseline, data-flow, finding/summary templates) and NIST SSDF PW.7 (review/analyze human-readable code, record/triage findings) ([SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final)). **Recommended** as taxonomy/process anchors, not drop-in skills.
5. **Convergent pattern across Gold sources:** (a) threat-model or risk triage first, (b) research whole codebase / baseline but **report only on the change**, (c) confidence gates and explicit false-positive exclusions, (d) structured findings with location + impact + fix, (e) progressive disclosure of checklists. Anthropic’s default prompt is **web-skewed and actively deprioritizes shell/CI secrets** in ways that fight our domain — invert those exclusions for Propraetor.
6. **Local baseline:** Cursor ships `/review-security` which launches a built-in `security-review` subagent ([docs](https://cursor.com/docs/security-agents), local skill at `~/.cursor/skills-cursor/review-security/SKILL.md`). Treat as product baseline, not a design source to copy blindly (prompt internals are not fully published as a SKILL.md).

---

## Search channels (what was checked)

| Channel | Result (high level) |
| --- | --- |
| [skills.sh](https://skills.sh/) + `npx skills find security` | Hits include Sentry `security-review`, Addy Osmani `security-and-hardening`, Firebase rules auditors, Better Auth, golang-security — **not** Trail of Bits on the leaderboard search path used here |
| `npx skills find "code review"` | Mostly general review (Matt Pocock, obra/superpowers), not security-first |
| `npx skills find appsec` / `owasp` | Mostly low-install / individual authors; GitHub `awesome-copilot` OWASP ASI skill; Oracle NetSuite OWASP skill |
| `npx skills find audit` / `sast` / `secrets` | SEO/audit noise; wshobson secrets-management; Ghost Security secret scan; few credible PR security-review skills |
| GitHub known orgs | Trail of Bits `skills` (6.4k★), Anthropic `claude-code-security-review` (5.7k★), Sentry `skills` (898★), Red Hat Product Security `prodsec-skills`, GitHub `awesome-copilot` |
| OWASP | Secure Code Review Cheat Sheet (maintained); Code Review Guide v2 PDF dated July 2017 ([project page](https://owasp.org/www-project-code-review-guide/)); ASVS 5.0 ([asvs.dev](https://asvs.dev/)) |
| Anthropic | `/security-review` + GH Action + security-guidance plugin ([docs](https://code.claude.com/docs/en/security-guidance.md), [blog](https://www.anthropic.com/news/automate-security-reviews-with-claude-code)) |
| Cursor | Security Agents docs, Automations templates, security-agents blog |
| OpenAI | Codex Security (research preview) product docs describe threat-model → validate → remediate; skill-like plugin commands documented under developers.openai.com/codex/security (fetch timed out in this session; secondary corroboration via Help Center search results — treat OpenAI deep internals as **Interesting** until re-fetched) |
| Semgrep / Snyk | Strong product blogs; Semgrep Assistant is SAST+LLM triage, not a portable SKILL.md; Snyk blogs critique/quote Cursor prompts but are secondary for methodology |
| NCC Group | No skill-like public artifact located in this pass |

---

## Candidate inventory

| Name | URL | Publisher | A | B highlights | C | Label |
| --- | --- | --- | --- | --- | --- | --- |
| Trail of Bits `differential-review` | [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md), [methodology](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/methodology.md), [adversarial](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/adversarial.md), [reporting](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/reporting.md) | Trail of Bits | High (security) → **Gold** with AI skill packaging | Full A–B: 7 phases, quality checklist, risk taxonomy, blast radius, exploit scenarios, report template, progressive docs | Medium–High: process is domain-agnostic; pattern refs skew Solidity/contracts — adapt triggers to shell/TF/IAM | **Gold** |
| Anthropic `/security-review` + GH Action | [security-review.md](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md), [README](https://github.com/anthropics/claude-code-security-review) | Anthropic | High (AI) + security practice → **Gold** | Diff-scoped; phases + parallel FP filter; confidence ≥0.8; severity; finding format; hard exclusion list | Medium: excellent FP discipline; **explicitly weak for our domain** (shell injection / secrets-on-disk / GHA often excluded) | **Gold** (invert exclusions) |
| Cursor Automations “Find vulnerabilities” | [workflow prompt](https://cursor.com/workflows/autonomous-agents/find-vulnerabilities), [blog](https://cursor.com/blog/security-agents), [Security Agents docs](https://cursor.com/docs/security-agents) | Cursor | High (AI) → **Gold** | 4-step workflow; attack-path discipline; severity gate; response rules (no fix PRs from review agent) | Medium: web-ish priority list; short = easy to fork with infra priorities | **Gold** |
| Sentry `security-review` | [SKILL.md](https://github.com/getsentry/skills/blob/main/skills/security-review/SKILL.md) | Sentry | High (AppSec vendor / eng org) | Research-vs-report; confidence levels; Do-Not-Flag; progressive refs; output contract | Medium: web-heavy refs; documents infra guides (docker present; terraform/ci-cd referenced but not all files present in tree at fetch time) | **Gold** |
| Sentry `gha-security-review` | [SKILL.md](https://github.com/getsentry/skills/blob/main/skills/gha-security-review/SKILL.md) | Sentry | High | Ordered checks; external-attacker threat model; 5-element PoC requirement; safe patterns | **High** for CI/supply-chain slice of Propraetor | **Recommended** |
| OWASP Secure Code Review Cheat Sheet | [cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Code_Review_Cheat_Sheet.html) | OWASP | High (security) | Baseline vs diff steps; data-flow; STRIDE/Top 10; finding + summary templates; SAST+manual | Medium: web AppSec-skewed; still best checklist substrate | **Recommended** |
| OWASP ASVS 5.0 | [asvs.dev](https://asvs.dev/) | OWASP | High | Requirement catalog + evidence expectations; not a review workflow | Low–Medium as skill body; useful for mapping findings | **Interesting** |
| OWASP Code Review Guide v2 | [project](https://owasp.org/www-project-code-review-guide/) | OWASP | High org, **stale artifact** (July 2017 PDF; Top 10 2013-era chapters) | Deep “how to review” narrative | Low for 2026 skill copy-paste | **Interesting** (history only) |
| NIST SSDF SP 800-218 (PW.7) | [CSRC](https://csrc.nist.gov/pubs/sp/800/218/final) | NIST | High | Organizational practice: review and/or analyze human-readable code; record/triage | Low as skill text; High as “why we exist” framing | **Recommended** (framing) |
| Anthropic security-guidance plugin | [docs](https://code.claude.com/docs/en/security-guidance.md) | Anthropic | High (AI) | Layered in-session review (pattern → turn → commit); custom guidance/patterns files | Medium: companion to PR review, not a PR skill; patterns web-skewed | **Recommended** (layering idea) |
| Addy Osmani `security-and-hardening` | [skills.sh](https://skills.sh/addyosmani/agent-skills/security-and-hardening), [SKILL.md](https://raw.githubusercontent.com/addyosmani/agent-skills/main/skills/security-and-hardening/SKILL.md) | Addy Osmani / Google Chrome DX (personal skill pack; large stars) | Medium–High (AI-in-SDLC via author/ecosystem; not a security lab) | STRIDE-first; Always/Ask/Never tiers; OWASP prevention patterns | Low–Medium: explicitly web-app oriented | **Interesting** |
| GitHub awesome-copilot `se-security-reviewer` | [agent](https://github.com/github/awesome-copilot/blob/main/agents/se-security-reviewer.agent.md) | GitHub community pack | Medium (GitHub-hosted; community content) | OWASP Top 10 / LLM Top 10 steps; plan-then-review | Low for infra | **Interesting** |
| GitHub awesome-copilot `agent-owasp-compliance` | [SKILL.md](https://github.com/github/awesome-copilot/blob/main/skills/agent-owasp-compliance/SKILL.md) | GitHub community pack | Medium | Ordered ASI Top 10 compliance checks | Wrong target (agent runtime, not PR code review) | **Interesting** (adjacent) |
| GitHub awesome-copilot `mcp-implementation-security-review` | [SKILL.md](https://github.com/github/awesome-copilot/blob/main/skills/mcp-implementation-security-review/SKILL.md) | GitHub community pack | Medium | Strong completion criteria; FP filters; MCP Top 10 | High if we review MCP servers; else niche | **Interesting** |
| GitHub awesome-copilot `threat-model-analyst` | [SKILL.md](https://github.com/github/awesome-copilot/blob/main/skills/threat-model-analyst/SKILL.md) | GitHub community pack | Medium | Heavy progressive disclosure; STRIDE-A; incremental mode | Overkill for PR skill; useful for baseline threat model | **Interesting** |
| Trail of Bits `supply-chain-risk-auditor` | [SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/supply-chain-risk-auditor/skills/supply-chain-risk-auditor/SKILL.md) | Trail of Bits | High | Clear workflow + risk criteria + report template | High for dependency posture; not PR diff review | **Recommended** (companion) |
| Red Hat `prodsec-skills` differential-review | [SKILL.md](https://github.com/RedHatProductSecurity/prodsec-skills/blob/main/module/skills/differential-review/SKILL.md) | Red Hat Product Security | High | Same ToB methodology, CC BY-SA, institutional redistribution | Same as ToB | **Gold** (same family) |
| OpenAI Codex Security | [developers.openai.com/codex/security](https://developers.openai.com/codex/security) (product); Help Center summary | OpenAI | High (AI) | Product workflow: threat model, validate in isolation, remediate; diff scan vs deep scan | Medium: closed product more than portable skill text | **Interesting** |
| Semgrep Assistant | [Semgrep blog](https://semgrep.dev/blog/2024/how-semgrep-assistant-is-driving-enterprise-adoption-of-ai-code-security) | Semgrep | High (security) | FP filtering + remediation on top of deterministic SAST | Idea: LLM should not replace rules engine | **Interesting** (architecture idea) |
| Snyk AI secure-dev blogs | e.g. [Cursor agents analysis](https://snyk.io/blog/cursor-security-agent-prompts/) | Snyk | High (vendor) | Quotes Cursor prompt; argues independent SAST under LLM | Secondary commentary; not a skill | **Interesting** (corroboration only) |
| hoodini / agamm OWASP skills | [skills.sh owasp hits](https://skills.sh/) | Individuals (~262–318★) | Medium at best | Checklist wrappers around OWASP | Web-skewed; thinner than Sentry/ToB | **Interesting** / weak Recommend |
| skill-security-review / Sigil / skill-audit / agentsec | Various GitHub | Individuals / niche | Fail–Low for *code* review purpose | These audit **agent skills** for malice, not PR code security | Wrong problem | **Discard** (different question) |
| Firebase / Better Auth security skills | skills.sh | Google Firebase / Better Auth | High org, wrong scope | Product-specific rule auditors | N/A for Propraetor | **Discard** |
| Vercel-adjacent skills on leaderboard | skills.sh | Vercel Labs etc. | Weak for security gate | Not security review | N/A | **Discard** |

---

## Deep dives (top candidates)

### 1. Trail of Bits `differential-review` — Gold

**Why steal it:** Most complete public *skill* for change-focused security review from a top-tier security firm (CC BY-SA 4.0). Progressive disclosure is textbook skill design: thin `SKILL.md` + `methodology.md` / `adversarial.md` / `reporting.md` / `patterns.md`.

**Process shape (from SKILL + methodology):**

```
Pre-Analysis → Phase 0 Triage → Phase 1 Code Analysis → Phase 2 Test Coverage
→ Phase 3 Blast Radius → Phase 4 Deep Context → Phase 5 Adversarial → Phase 6 Report
```

**Stealable pieces:**

- **Anti-rationalization table** (“Small PR, quick review” / “Just a refactor”) forcing risk-based depth ([SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md)).
- **Risk triggers:** HIGH = auth, crypto, external calls, value transfer, validation removal; LOW = comments, tests, UI, logging.
- **Git blame on removed code** and regression detection (`git log -S`) — critical for “security check deleted” bugs ([methodology](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/methodology.md)).
- **Test coverage elevates risk** (new function + no tests → elevate).
- **Blast radius** quantitative priority matrix.
- **Adversarial phase:** WHO/ACCESS/INTERFACE → attack vector → exploitability EASY/MEDIUM/HARD → concrete PoC ([adversarial.md](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/adversarial.md)).
- **Completion criteria:** quality checklist (all changed files, blame on removals, blast radius for HIGH, concrete scenarios, line+commit refs, report file written).
- **Output contract:** executive summary with APPROVE/REJECT/CONDITIONAL, findings with historical context, methodology/limitations/confidence section ([reporting.md](https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/reporting.md)).

**Caveat for us:** Examples and pattern docs lean smart-contract (reentrancy, `onlyOwner`). **Inference:** keep the *workflow*, rewrite risk triggers and patterns for shell, Terraform, Podman, IAM, CI, secrets.

**Confidence:** High — primary files read in full.

### 2. Anthropic `claude-code-security-review` — Gold

**Why steal it:** First-party AI vendor artifact explicitly designed for PR/diff security review, with published prompt, GH Action, and false-positive filter architecture ([README](https://github.com/anthropics/claude-code-security-review), [prompt](https://github.com/anthropics/claude-code-security-review/blob/main/.claude/commands/security-review.md)).

**Stealable pieces:**

- **Objective:** high-confidence, newly introduced issues only; not general code review.
- **Analysis methodology:** (1) repository context research, (2) comparative analysis vs existing secure patterns, (3) vulnerability assessment / data-flow.
- **Execution pattern:** sub-task finds vulns → parallel sub-tasks FP-filter each → drop confidence &lt; 8 (on 1–10 scale) / below 0.7 on alternate scale in same doc.
- **Finding format:** file:line, severity, category slug, description, exploit scenario, recommendation.
- **Severity:** HIGH / MEDIUM / LOW with impact definitions.
- **Hard exclusion list** (DoS, rate limits, dependency CVEs managed elsewhere, docs-only, theoretical races, etc.) — strong FP discipline.

**Anti-patterns relative to Propraetor (do *not* copy blindly):**

- Precedent: “Command injection vulnerabilities in shell scripts are generally not exploitable… Only report … if … very specific attack path for untrusted input.”
- Exclusion: “Secrets or credentials stored on disk if they are otherwise secured” / “Secrets or sensitive data stored on disk (these are handled by other processes).”
- Soft-pedals many GitHub Actions findings unless “concrete and has a very specific attack path.”
- Environment variables and CLI flags treated as trusted.

**Inference:** Anthropic optimized for *web product PR noise reduction*. For an infra/shell/TF repo, those defaults would systematically under-report our highest-risk classes. Steal the **structure**; replace the **exclusion set** with an infra threat model (and keep Sentry GHA skill’s external-attacker model for workflows).

Also note: README warns the Action is **not hardened against prompt injection** and should only review trusted PRs ([README Security Considerations](https://github.com/anthropics/claude-code-security-review)).

**Companion:** [security-guidance plugin](https://code.claude.com/docs/en/security-guidance.md) — pattern match on edit, end-of-turn diff review, agentic commit review; project files `.claude/claude-security-guidance.md` and `security-patterns.yaml`. Steal the **defense-in-depth layering** (inner loop vs on-demand `/security-review` vs CI), not the web pattern list.

**Confidence:** High for the published command file; High for plugin docs.

### 3. Cursor Automations security templates — Gold

**Primary:** [Find vulnerabilities workflow](https://cursor.com/workflows/autonomous-agents/find-vulnerabilities) publishes the full marketplace prompt. [Security agents blog](https://cursor.com/blog/security-agents) describes four agents (Agentic Security Review, Vuln Hunter, Anybump, Invariant Sentinel) and a security MCP for persistence/dedup/Slack. [Security Agents product docs](https://cursor.com/docs/security-agents) describe Security Reviewer vs Vulnerability Scanner and `/review-security`.

**Stealable prompt pattern (verbatim structure):**

1. Inspect PR diff and surrounding paths.  
2. For every candidate, trace attacker-controlled input to the real sink.  
3. Verify existing controls (auth, schema, escaping, parameterization, allowlists).  
4. Report only medium/high/critical with plausible attack path + concrete evidence.  

Plus response rules: re-validate prior threads, inline comments only, Slack summary, **do not push fixes from the review workflow**.

**Stealable product ideas (from blog, not required for a local skill):** separate security review from general Bugbot; escalate from Slack-only → PR comments → blocking gate once FP rate is proven; invariant drift agent with memory; dependency remediation as a *different* automation.

**Baseline in this environment:** `~/.cursor/skills-cursor/review-security/SKILL.md` only orchestrates the opaque `security-review` subagent (prompt shape: Full Repository Path / Diff / Base Branch / Custom Instructions). **Not** a methodology source.

**Confidence:** High for published workflow prompt and blog; Low for closed subagent internals (by design out of scope).

### 4. Sentry `security-review` (+ `gha-security-review`) — Gold / Recommended

**Why steal it:** Production engineering org skill with **research vs reporting** split, confidence taxonomy, extensive Do-Not-Flag table (server-controlled config ≠ attacker input), and progressive disclosure into `references/` + `languages/` + `infrastructure/` ([SKILL.md](https://github.com/getsentry/skills/blob/main/skills/security-review/SKILL.md)). Credits OWASP Cheat Sheet Series (CC BY-SA).

**Stealable pieces:**

- Report only HIGH confidence; MEDIUM → “Needs verification”; LOW → omit.
- Context detection → load only relevant reference packs (progressive disclosure).
- Output: Summary + Findings (`VULN-001`) + Needs Verification (`VERIFY-001`); “No high-confidence vulnerabilities identified” when empty.
- Docker infrastructure reference actually present ([docker.md](https://github.com/getsentry/skills/blob/main/skills/security-review/infrastructure/docker.md)): non-root USER, pin digests, no secrets in images — directly relevant.

**`gha-security-review` steal list:**

- Threat model: **external attacker without write access** (fork PRs, issues, comments) — explicitly excludes `workflow_dispatch`-only issues.
- Every HIGH finding needs entry point, payload, execution mechanism, impact, PoC sketch — else MEDIUM.
- Ordered vulnerability classes: pwn request, expression injection, unauthorized commands, credential escalation, config-file poisoning (`CLAUDE.md` / `AGENTS.md` / Makefiles), supply chain, permissions/secrets, runners.
- Safe-pattern table (numeric PR number in `run:` is OK; `${{ }}` in `if:`/`with:` often OK).

**Note:** At fetch time the skill tree listed `infrastructure/docker.md` and language guides, but `terraform.md` / `ci-cd.md` / `cloud.md` referenced in SKILL.md were **not** present in the git tree (404). Steal the *design* of infra progressive disclosure; do not assume those files exist yet.

**Confidence:** High for SKILL.md and gha skill; Medium for incomplete infra pack.

### 5. OWASP Secure Code Review Cheat Sheet (+ ASVS / Guide) — Recommended

**Cheat sheet** ([primary](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Code_Review_Cheat_Sheet.html)):

- Distinguishes **baseline** vs **diff-based** reviews; gives separate preparation and step lists for each.
- Diff steps: impact on existing controls, new attack vectors, trust boundaries, integrations, regression, apply patterns.
- Techniques: code pattern analysis, data-flow (sources → sinks → trust zones), STRIDE / Top 10 / abuse cases, business logic.
- **Finding report template** (Title, Severity, CWE, Location, Description, Impact, Reproduction, Recommendation, References, Status…).
- **Review summary template** (scope, counts by severity, key recommendations, overall risk).
- Explicitly positions manual review as complement to SAST/DAST.

**ASVS 5.0** ([asvs.dev](https://asvs.dev/)): verification *requirements* catalog (~350 reqs, 17 chapters) — use as optional mapping target for findings, not as the skill’s main loop. Emphasizes evidence and that “merely running an automated tool” is insufficient for certification-style verification (**Inference:** same bar applies to LLM-only laundry lists).

**Code Review Guide v2:** still linked from OWASP; dated July 2017 and Top 10 2013-oriented ([project page](https://owasp.org/www-project-code-review-guide/)). Useful historical method depth; prefer Cheat Sheet for maintained checklists.

**Confidence:** High for cheat sheet content fetched; High that Guide is stale relative to 2025 Top 10 / ASVS 5.0.

### 6. NIST SSDF PW.7 — Recommended framing

[NIST SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final) defines practice **PW.7**: review and/or analyze human-readable code (including scripts) to identify vulnerabilities and verify compliance with security requirements; use humans and/or tools; record and triage issues in the team workflow. **Inference:** legitimizes an agent skill as one implementation of PW.7, not a replacement for recorded triage/human judgment. Not skill-shaped itself.

### 7. Adjacent but useful — Recommended / Interesting

- **ToB `supply-chain-risk-auditor`:** maintainer concentration, staleness, past CVEs, missing SECURITY.md — good companion skill for lockfile/action pin reviews, not a substitute for differential review ([SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/supply-chain-risk-auditor/skills/supply-chain-risk-auditor/SKILL.md)).
- **Addy Osmani `security-and-hardening`:** STRIDE-at-boundaries + Always/Ask/Never tiers — good *authoring-time* skill; weak as PR security reviewer ([SKILL.md](https://raw.githubusercontent.com/addyosmani/agent-skills/main/skills/security-and-hardening/SKILL.md)).
- **OpenAI Codex Security:** product narrative of threat-model → validate (incl. isolated reproduction) → remediate; `SECURITY.md` as policy context ([developers.openai.com/codex/security](https://developers.openai.com/codex/security)). **Confidence Medium** this session (primary fetch timeout; corroborated by OpenAI Help Center / docs search snippets).
- **Semgrep Assistant:** architectural lesson — deterministic engine + LLM for FP/remediation ([blog](https://semgrep.dev/blog/2024/how-semgrep-assistant-is-driving-enterprise-adoption-of-ai-code-security)). Pair any LLM skill with ShellCheck/TFLint/secret scanners where possible.

---

## Convergent methodology pattern

Across Gold sources, a skill-worthy security review converges on:

| Stage | What credible sources do |
| --- | --- |
| Scope | Diff/PR first; whole-repo research only to prove exploitability (Anthropic, Cursor, Sentry, OWASP diff-based) |
| Triage | Risk-rank changed surfaces before deep work (ToB Phase 0; Sentry context detect) |
| Analysis | Input→sink tracing; compare to existing controls/patterns; git history on removals (ToB, Cursor, Anthropic) |
| Adversarial check | Concrete attacker model + steps for HIGH risk (ToB Phase 5; Sentry GHA five elements) |
| Filter | Explicit confidence thresholds and hard exclusions (Anthropic, Sentry, Cursor) |
| Output | Structured findings + severity + evidence + fix; state “none found” cleanly; optional APPROVE/REJECT (ToB, OWASP templates) |
| Done when | Checklist: scoped files covered, FP filter applied, report/artifact produced (ToB quality checklist; OWASP summary) |
| Disclosure | Core steps short; taxonomies in sidecar files (ToB, Sentry) |

---

## Gaps for our infra domain

No Gold primary artifact fully covers Propraetor’s threat surface as a single skill. Specific gaps:

1. **Shell as first-class attack surface.** Anthropic’s default prompt *discourages* shell command-injection findings; ToB examples are contract-centric; Sentry’s shell guidance is thin compared to web injection refs.
2. **Terraform / IAM / cloud policy as review taxonomy.** Sentry *names* terraform/cloud guides but files were missing at fetch; no High-credibility portable TF security-review skill found on skills.sh comparable to ToB differential-review.
3. **Container/host isolation & bind-mount DAC.** Docker non-root tips exist (Sentry docker.md); little on rootless Podman, user namespaces, or “writable bind mount = host write” in skill form (related research lives in this repo’s sandbox note, not in external skills).
4. **Secrets policy for infra repos.** Anthropic excludes many “secrets on disk” cases; we need the opposite for `.env` leakage, example vs real secrets, CI secret exfil — without turning the skill into a generic secret scanner (pair with tools).
5. **CI/agent instruction poisoning.** Sentry GHA skill is the best public treatment (`AGENTS.md` / `CLAUDE.md` loaded from PR). General security-review skills barely mention it.
6. **Pre-stability / breaking-change posture.** No external skill discusses “no backwards-compat shims” interacting with security (e.g. dual-read of secrets). Domain-specific.
7. **Skill-ecosystem noise.** Many skills.sh “security” hits audit *skills themselves* (Sigil, skill-audit) or product niches (Firebase rules) — easy to confuse with PR code review.

**Inference:** Design our skill as a **ToB-shaped differential workflow** + **Anthropic/Cursor confidence gates** + **Sentry progressive references**, with an **infra-first taxonomy** (shell, Terraform, IAM, containers, CI, secrets, supply chain) and Anthropic-style exclusions **rewritten**, not copied.

---

## Ranked shortlist (inspiration)

1. **Trail of Bits `differential-review` (+ Red Hat redistribution)** — process, checklists, report, progressive docs  
2. **Anthropic `security-review.md`** — FP discipline, multi-phase agent pattern, finding schema (**rewrite exclusions**)  
3. **Cursor Find-vulnerabilities Automations prompt** — minimal high-signal PR loop; product layering ideas from [security-agents blog](https://cursor.com/blog/security-agents)  
4. **Sentry `security-review` + `gha-security-review`** — confidence model, progressive refs, CI threat model  
5. **OWASP Secure Code Review Cheat Sheet** — baseline/diff methodology + finding/summary templates  
6. **NIST SSDF PW.7** — organizational framing  
7. **ToB `supply-chain-risk-auditor`** — companion for dependency/action risk  
8. **Anthropic security-guidance plugin docs** — in-session vs PR vs CI layering  

Local **Cursor `/review-security` / `security-review` subagent**: baseline to compare against after we design ours; not a primary methodology source.
