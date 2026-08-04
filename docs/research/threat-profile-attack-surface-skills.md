# Threat-profile, attack-surface, and construction-soundness agent skills

**Researched:** 2026-08-04  
**Question:** What credible, publicly available agent skills / playbooks / prompt packs exist for assessing a system’s **overall threat profile, attack surfaces, and ownership of those surfaces** — i.e. **construction soundness** / architectural security assessment — rather than hunting individual vulnerabilities in a PR diff?  
**Scope:** Open skills ecosystem (skills.sh / GitHub Agent Skills / Claude/Cursor skills); threat-modeling and attack-surface methodologies from credible security orgs that could be embodied as a skill; AI-lab artifacts that ship skill-like workflows for system/component security posture. Prefer artifacts with ordered process, completion criteria, taxonomy, ownership hooks, and an output contract. Out of scope: writing our skill; re-deep-diving PR/diff vuln-hunting skills already covered in [`security-review-agent-skills.md`](./security-review-agent-skills.md) (mention only as contrast).  
**Method:** Primary sources only. Rubric A/B/C applied to every candidate (documented below). Channels searched: [skills.sh](https://skills.sh/) + `npx skills find` for threat model / threat modeling / attack surface / STRIDE / architecture security / security design / trust boundary / PASTA / ATT&CK / security architecture; GitHub known orgs (OpenAI, Anthropic, Trail of Bits, GitHub awesome-copilot, Google Mantis, AWS, Bitwarden, Microsoft hve-core, Red Hat); classic methodology substrates (Microsoft SDL/STRIDE, OWASP Threat Modeling + Attack Surface Analysis, NIST SP 800-154 / SSDF PW.1, PASTA, ATT&CK, CISA Secure by Design, Threat Modeling Manifesto); architecture-review / ownership playbooks. Claims cite owning URLs; inferences are labeled.

---

## Assessment methodology

Every candidate is scored on three axes. Scores are **High / Medium / Low / Fail**, with evidence.

### A. Source credibility (gate)

**Fail excludes** the candidate from “recommended inspiration.”

Score **High** only if at least one of:

1. **Security credibility:** OWASP, CISA, NIST, CERT/SEI, major cloud security teams, established AppSec/security firms (Trail of Bits, NCC Group, Semgrep, Snyk, GitHub Security, Microsoft SDL, Bitwarden AppSec, UK NCSC / ASD ACSC via published Secure-by-Design packs, etc.), academic security labs.
2. **AI-in-SDLC credibility:** Anthropic, OpenAI, Google, Microsoft/GitHub Copilot, Cursor, comparable labs.

**Both** dimensions → flag as **Gold**.

**Fail:** anonymous gist, weak affiliation, SEO farms, aggregators without primary artifacts, geoscience/pasta-name collisions, product-niche auditors unrelated to construction soundness.

### B. Artifact quality (threat-profile / construction-soundness skill inspiration)

1. **Process shape** — ordered threat-model / surface-inventory workflow vs freeform advice  
2. **Completion criteria** — how the model/surface map is “done enough”  
3. **Taxonomy** — STRIDE, LINDDUN, PASTA, ATT&CK, custom surface taxonomy, trust zones  
4. **System vs change scope** — whole architecture / component / attack surface (not PR bugs)  
5. **Ownership / accountability** — assigns or requires owners for surfaces/controls  
6. **Output contract** — threat model doc, surface inventory, DFD, risk register, architecture security notes  
7. **Evidence / legwork** — diagramming, inventory from code/config, interviews, tool-assisted surface discovery  
8. **Progressive disclosure** — core steps vs deep reference  

### C. Applicability to Propraetor

Fit for a **pre-stability infra/shell/Terraform/Podman/CI** repo: Host vs Guest, volumes, IAM, secrets, containers, supply chain, agent instruction poisoning. Prefer candidates that map to **infra construction** over web AppSec threat models — note skew explicitly.

**Inventory labels:** Gold / Recommended / Interesting / Discard.

---

## Verdict

1. **Best portable *skill* for repo-grounded construction soundness is OpenAI’s curated `security-threat-model`** ([SKILL.md](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/SKILL.md), [prompt template](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/references/prompt-template.md), redistributed by Trail of Bits as [openai-security-threat-model](https://github.com/trailofbits/skills-curated/tree/main/plugins/openai-security-threat-model), [skills.sh](https://skills.sh/openai/skills/security-threat-model) ~3.9K installs). Ordered 8-step workflow: scope → boundaries/assets/entry points → attacker calibration → abuse paths → prioritize → **pause for owner/context validation** → mitigations → quality checklist; evidence anchors; runtime vs CI/dev split; Mermaid DFD; focus-path list for later manual review. **Gold.**
2. **Best litmus test + shared schema + ownership interview modes is Anthropic’s `/threat-model` skill** in [defending-code-reference-harness](https://github.com/anthropics/defending-code-reference-harness/tree/main/.claude/skills/threat-model) ([SKILL.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/SKILL.md), [schema.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/schema.md), [bootstrap.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/bootstrap.md)). Explicitly separates **threat** (survives a one-line patch) from **vulnerability**; four-question interview + code bootstrap with **Infra reader** (Terraform, Docker, CI, IAM) and supply-chain surfaces; fixed `THREAT_MODEL.md` contract with actors, surfaces, assets, status, evidence. **Gold.**
3. **Best engineering-org playbook for ownership + architecture review is Bitwarden’s pair** — [`threat-modeling`](https://github.com/bitwarden/ai-plugins/blob/main/plugins/bitwarden-security-engineer/skills/threat-modeling/SKILL.md) (4-phase engagement, Security Definitions with attacker capabilities *and* limitations, ADR alignment, when to escalate to AppSec) and [`reviewing-security-architecture`](https://github.com/bitwarden/ai-plugins/blob/main/plugins/bitwarden-security-engineer/skills/reviewing-security-architecture/SKILL.md) (trust-boundary validation checklist, anti-patterns). **Recommended** (security-org High; web/product skew).
4. **Best heavyweight STRIDE-A / DFD report factory is GitHub awesome-copilot `threat-model-analyst`** ([SKILL.md](https://github.com/github/awesome-copilot/blob/main/skills/threat-model-analyst/SKILL.md), [orchestrator](https://github.com/github/awesome-copilot/blob/main/skills/threat-model-analyst/references/orchestrator.md)) — 10-step workflow, Mermaid DFDs, incremental mode, verification gates. Credibility is **Medium** (community pack on GitHub org, not a security lab). Steal structure; do not treat as Gold authority. **Interesting → conditional Recommend** for output-contract ideas.
5. **Methodology substrates (not skills, but steal shapes):** [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/) / Shostack 4Q; OWASP [Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html) + [Attack Surface Analysis Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html); Microsoft SDL [five steps + STRIDE](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling); NIST SSDF **PW.1** (threat/attack/surface modeling) + **PO.2** (roles/responsibilities) ([SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final)); NIST draft [SP 800-154](https://csrc.nist.gov/pubs/sp/800/154/ipd) data-centric 4-step model; CISA [Secure by Design](https://www.cisa.gov/securebydesign); Microsoft hve-core [`secure-by-design` / SBD-08 Minimize Attack Surface](https://github.com/microsoft/hve-core/blob/main/.github/skills/security/secure-by-design/references/08-minimize-attack-surface.md). **Recommended** as taxonomy/process anchors.
6. **Convergent pattern for *threat-profile* skills:** (a) model the system (components, DFDs, trust boundaries, assets, entry points) with evidence; (b) calibrate attacker capabilities *and* non-capabilities; (c) enumerate threats as abuse paths / STRIDE classes that survive individual patches; (d) inventory / reduce attack surface; (e) assign or solicit owners and open questions; (f) emit a living artifact + completion checklist — **not** a vuln finding list. Contrast with [security-review research](./security-review-agent-skills.md): that class scopes to the *diff* and demands sink-level exploitability.
7. **Gap:** Almost no Gold skill requires a **RACI / control-owner map** for surfaces (who owns which volume, credential, CI trigger, Host control plane). Closest hooks: Anthropic/OpenAI owner interview questions; Bitwarden escalate-to-AppSec rules; NIST PO.2. Propraetor will need a custom ownership layer.

---

## Contrast box — threat-profile vs vuln-finding skills

Foil: prior note [`security-review-agent-skills.md`](./security-review-agent-skills.md) (ToB `differential-review`, Anthropic `/security-review`, Cursor Find-vulnerabilities, Sentry `security-review`).

- **Question answered:** “Is this ship built soundly — where are the boundaries, assets, and blast radii?” vs “Did this PR introduce a reachable vulnerability?”
- **Unit of analysis:** Architecture / component / attack surface / trust zone vs changed lines and input→sink paths.
- **Survival test:** Anthropic threat-model litmus — if a one-line patch removes the row, it was a *vuln*, not a *threat* ([SKILL.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/SKILL.md)) vs vuln skills that *want* file:line exploit scenarios.
- **Output:** Living `THREAT_MODEL.md` / DFD / surface inventory / Security Definitions vs structured `VULN-00N` findings with severity and fix.
- **Done criteria:** Entry points and trust boundaries covered; assumptions explicit; owner questions resolved or parked vs confidence gates + false-positive exclusion lists on the *diff*.

Adjacent companions from the prior note that *feed* threat-profile work but are not substitutes: ToB [`supply-chain-risk-auditor`](https://github.com/trailofbits/skills/blob/main/plugins/supply-chain-risk-auditor/skills/supply-chain-risk-auditor/SKILL.md) (dependency posture), ToB [`audit-context-building`](https://github.com/trailofbits/skills/blob/main/plugins/audit-context-building/skills/audit-context-building/SKILL.md) (pure system comprehension before hunting), Sentry `gha-security-review` (CI slice threat model). Do **not** re-use Anthropic `/security-review` exclusions as a threat-model baseline — they actively deprioritize shell/CI/secrets classes Propraetor cares about.

---

## Search channels (what was checked)

| Channel | Result (high level) |
| --- | --- |
| [skills.sh](https://skills.sh/) + `npx skills find "threat model"` | **OpenAI `security-threat-model`** (~3.9K), **GitHub `threat-model-analyst`** (~1.3K), **Anthropic defending-code-reference-harness `threat-model`** (~850), **AWS Security Agent threat-modeling** (~512), **Google Mantis `mantis-threat-model`** (~367), plus low-install individual packs |
| `npx skills find "attack surface"` | Microsoft Docs Azure EASM skill (product ops); individual ASM/pentest recon skills — mostly **Discard** for construction-soundness inspiration |
| `npx skills find STRIDE` | `wshobson/agents@stride-analysis-patterns` (~9.5K) — pattern pack; forks; individual “threat-modelling” wrappers |
| `npx skills find PASTA` / `ATT&CK` | Name collisions (geoscience `pastas`); thin individual PASTA skill packs — not primary PASTA methodology |
| `npx skills find "security architecture"` / `"security design"` | Bitwarden `reviewing-security-architecture`; Microsoft `hve-core` `secure-by-design`; individual authors |
| `npx skills find "trust boundary"` | Weak / product-niche hits |
| GitHub known orgs | OpenAI skills curated; Anthropic defending-code-reference-harness; ToB skills + skills-curated; GitHub awesome-copilot; Google mantis; AWS agent-toolkit; Bitwarden ai-plugins; Microsoft hve-core |
| OWASP | [Threat Modeling Project](https://owasp.org/www-project-threat-modeling/), [Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html), [Attack Surface Analysis](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html), [Threat Modeling Playbook](https://owasp.org/www-project-threat-modeling-playbook/) (donated markdown; roadmap stale), ASVS architecture chapter (V1 historically; ASVS 5 reorganized — use as requirement catalog) |
| Microsoft SDL | [Threat modeling](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling), [Secure by Design / STRIDE](https://www.microsoft.com/en-us/securityengineering/sdl/practices/secure-by-design), [Threat Modeling Tool](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool) |
| NIST / CISA | [SP 800-218 SSDF](https://csrc.nist.gov/pubs/sp/800/218/final) PW.1 / PO.2; draft [SP 800-154](https://csrc.nist.gov/pubs/sp/800/154/ipd); [CISA Secure by Design](https://www.cisa.gov/securebydesign) |
| PASTA / ATT&CK | VerSprite PASTA pages + Wiley book as canonical; ATT&CK as technique vocabulary (not a full TM skill) |
| Ownership / RACI | Primary institutional hooks in NIST PO.2 and C-SCRM RACI language; few *skills* encode surface ownership |

---

## Candidate inventory

| Name | URL | Publisher | A | B highlights | C | Label |
| --- | --- | --- | --- | --- | --- | --- |
| OpenAI `security-threat-model` | [SKILL](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/SKILL.md), [prompt-template](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/references/prompt-template.md), [controls/assets](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/references/security-controls-and-assets.md), [ToB redistrib](https://github.com/trailofbits/skills-curated/tree/main/plugins/openai-security-threat-model) | OpenAI (+ ToB curated mirror) | High AI → **Gold** with security packaging via ToB redistrib | Full B: 8-step process, quality checklist, abuse paths, trust boundaries, owner pause, Markdown + Mermaid contract, evidence anchors, progressive refs | Medium–High: runtime/CI split and CLI/daemon examples help infra; still AppSec-phrased | **Gold** |
| Anthropic `/threat-model` (defending-code harness) | [skill dir](https://github.com/anthropics/defending-code-reference-harness/tree/main/.claude/skills/threat-model), [SKILL](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/SKILL.md), [schema](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/schema.md), [bootstrap](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/bootstrap.md) | Anthropic | High AI + security research harness → **Gold** | Threat≠vuln litmus; interview/bootstrap/bootstrap-then-interview; schema enums; STRIDE gap-fill; infra + supply-chain surface mappers; completion via schema sections | **High** for Propraetor: Infra reader explicitly covers `*.tf`, Docker, CI, IAM; actors include `supply_chain` | **Gold** |
| Bitwarden `threat-modeling` | [SKILL](https://github.com/bitwarden/ai-plugins/blob/main/plugins/bitwarden-security-engineer/skills/threat-modeling/SKILL.md) | Bitwarden | High (security product / AppSec eng) | 4-phase engagement; SD = threat model + goals + accepted status; STRIDE; templates; anti-verbosity; escalate triggers | Medium: product/crypto skewed; ownership via AppSec engagement is stealable | **Recommended** |
| Bitwarden `reviewing-security-architecture` | [SKILL](https://github.com/bitwarden/ai-plugins/blob/main/plugins/bitwarden-security-engineer/skills/reviewing-security-architecture/SKILL.md) | Bitwarden | High | Trust-boundary checklist; authZ layers; data classification; ADR alignment; feeds TM | Medium: web/token/crypto heavy | **Recommended** |
| GitHub awesome-copilot `threat-model-analyst` | [SKILL](https://github.com/github/awesome-copilot/blob/main/skills/threat-model-analyst/SKILL.md), [orchestrator](https://github.com/github/awesome-copilot/blob/main/skills/threat-model-analyst/references/orchestrator.md) | GitHub community pack | Medium | Extremely strong B: 10 steps, STRIDE-A, DFD skeletons, incremental mode, verification checklist, inventory JSON | Medium: deployment classification helps; overbuilt for small infra repo | **Interesting** (steal contract; gate A not Gold) |
| Trail of Bits `audit-context-building` | [SKILL](https://github.com/trailofbits/skills/blob/main/plugins/audit-context-building/skills/audit-context-building/SKILL.md) | Trail of Bits | High | Process + completeness checklist; trust-boundary mapping in Phase 3; **explicitly non-vuln** | Medium–High as precursor phase; contract-centric examples | **Recommended** (precursor) |
| Trail of Bits `supply-chain-risk-auditor` | [SKILL](https://github.com/trailofbits/skills/blob/main/plugins/supply-chain-risk-auditor/skills/supply-chain-risk-auditor/SKILL.md) | Trail of Bits | High | Workflow + risk criteria + report | High for one surface class (deps/actions) | **Recommended** (companion surface) |
| Google Mantis `mantis-threat-model` | [SKILL](https://github.com/google/mantis/blob/main/mantis-threat-model/SKILL.md) | Google | High AI | KB-only synthesis: trust boundaries, actors, assets, deployment intent checklist, provenance stamps | Low–Medium standalone (requires Mantis KB pipeline); strong *living model* ideas | **Interesting** / **Recommended** for pipeline staging |
| AWS Security Agent threat-modeling skill | [SKILL](https://github.com/aws/agent-toolkit-for-aws/blob/main/plugins/aws-agents-for-devsecops/skills/threat-modeling-with-aws-security-agent/SKILL.md) | AWS | High (cloud security) | STRIDE via managed product; spec+code upload workflow | Low as portable skill (S3 + `aws securityagent` API); cloud-product coupled | **Interesting** |
| Microsoft hve-core `secure-by-design` (+ SBD-08) | [SKILL](https://github.com/microsoft/hve-core/blob/main/.github/skills/security/secure-by-design/SKILL.md), [SBD-08](https://github.com/microsoft/hve-core/blob/main/.github/skills/security/secure-by-design/references/08-minimize-attack-surface.md) | Microsoft (UK Gov + ASD sources) | High | Principle checklists; minimize attack surface; governance; not a full TM workflow | Medium: policy substrate for surface reduction | **Recommended** (surface-reduction substrate) |
| Microsoft SDL threat modeling | [SDL page](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling), [Secure by Design](https://www.microsoft.com/en-us/securityengineering/sdl/practices/secure-by-design), [TMT](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool) | Microsoft | High | 5 steps; STRIDE; DFD-centric design analysis | Medium–High methodology; tool is Windows-centric | **Recommended** (substrate) |
| OWASP Threat Modeling Cheat Sheet | [cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html) | OWASP | High | 4Q → decompose / identify / mitigate / validate; STRIDE; cloud shared-responsibility note | Medium: AppSec default; cloud shared-responsibility maps to Host/Guest | **Recommended** |
| OWASP Attack Surface Analysis Cheat Sheet | [cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html) | OWASP | High | Surface definition; bucket/count method; change triggers; RSQ mention; recursive link to TM | **High** for Propraetor surface inventory shape | **Recommended** |
| OWASP Threat Modeling Project + Manifesto | [project](https://owasp.org/www-project-threat-modeling/), [manifesto](https://www.threatmodelingmanifesto.org/) | OWASP / working group | High | 4Q; values/principles; methodology-agnostic | High as framing; not a skill | **Recommended** (framing) |
| OWASP Threat Modeling Playbook | [project](https://owasp.org/www-project-threat-modeling-playbook/) | OWASP (Toreon donation) | High org; **stale roadmap** (1.1 by end of 2023 promised) | Org playbook intent | Low currency for skill copy-paste | **Interesting** (history) |
| NIST SSDF SP 800-218 PW.1 + PO.2 | [CSRC](https://csrc.nist.gov/pubs/sp/800/218/final) | NIST | High | PW.1 = threat/attack/surface modeling; PO.2 = roles & responsibilities / code owners | High for *why ownership belongs in the skill* | **Recommended** (framing + ownership) |
| NIST SP 800-154 (draft) | [IPD](https://csrc.nist.gov/pubs/sp/800/154/ipd) | NIST | High | 4-step data-centric TM: characterize data → attack vectors → controls → analyze | Medium: data-centric; draft status | **Recommended** (substrate) |
| CISA Secure by Design | [hub](https://www.cisa.gov/securebydesign), [principles PDF](https://www.cisa.gov/sites/default/files/2023-04/principles_approaches_for_security-by-design-default_508_0.pdf) | CISA (+ partners) | High | Manufacturer ownership of security outcomes; tailored threat models; SSDF pointer | Medium as skill text; High for “producer owns the surface” culture | **Recommended** (ownership culture) |
| PASTA (VerSprite / Wiley) | [VerSprite](https://versprite.com/cybersecurity-listings/devsecops/pasta-threat-modeling/) | VerSprite / UcedaVélez & Morana | High (established methodology) | 7 stages; business-risk + attack simulation; ATT&CK-friendly Stage 4 | Low–Medium as *agent skill*; book-heavy | **Interesting** (stage shape) |
| MITRE ATT&CK | [attack.mitre.org](https://attack.mitre.org/) | MITRE | High | Technique vocabulary for adversary capabilities — not a TM process | Medium: frame Host/CI actor techniques | **Interesting** (taxonomy only) |
| Addy Osmani `security-and-hardening` | [skills.sh](https://skills.sh/addyosmani/agent-skills/security-and-hardening) | Addy Osmani | Medium–High AI ecosystem | STRIDE-at-boundaries; Always/Ask/Never | Low–Medium: web hardening | **Interesting** |
| `wshobson` STRIDE analysis patterns | [skills.sh](https://skills.sh/wshobson/agents/stride-analysis-patterns) | Individual (high installs) | Medium | Pattern library around STRIDE | Thin process/ownership | **Interesting** |
| Individual PASTA / ASM / pentest-recon skills | skills.sh hits | Individuals | Fail–Low | Often vuln recon or SEO wrappers | Wrong problem or weak A | **Discard** |
| Firebase / Better Auth security skills | skills.sh | Product orgs | High org, wrong scope | Product rule auditors | N/A | **Discard** |

---

## Deep dives (top candidates)

### 1. OpenAI `security-threat-model` — Gold

**Why steal it:** Clearest public *portable* skill for AppSec-grade, repo-grounded threat modeling from an AI lab, with Trail of Bits redistribution confirming security-community packaging ([ToB curated README](https://github.com/trailofbits/skills-curated/blob/main/plugins/openai-security-threat-model/README.md)). Trigger discipline: only when the user asks to threat-model — not for general architecture summaries.

**Process shape (from [SKILL.md](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/SKILL.md)):**

```
1 Scope & system model → 2 Boundaries, assets, entry points → 3 Calibrate assets & attacker capabilities
→ 4 Enumerate threats as abuse paths → 5 Prioritize (L×I) → 6 Validate assumptions with user
→ 7 Recommend mitigations → 8 Quality check → write <name>-threat-model.md
```

**Stealable pieces:**

- **Evidence rule:** no invented components/flows/controls; every architectural claim needs a repo evidence anchor ([prompt-template](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/references/prompt-template.md)).
- **Scope discipline:** separate production/runtime vs CI/build/dev vs tests/examples; separate attacker- vs operator- vs developer-controlled inputs.
- **Trust boundaries as concrete edges** with protocol, auth, encryption, validation, rate limiting.
- **Attacker non-capabilities** to avoid inflated severity.
- **Owner/context pause:** 1–3 questions (service owner, deployment, exposure, authn/authz, data sensitivity, multi-tenancy) before final report — closest built-in **ownership solicitation** among Gold skills.
- **Quality checklist:** all entry points covered; each trust boundary appears in threats; assumptions explicit; format matches template.
- **Downstream focus paths:** 2–30 repo paths for deeper manual review — bridges threat profile → later vuln hunting without conflating them.
- **Asset/control taxonomy** in [security-controls-and-assets.md](https://github.com/openai/skills/blob/main/skills/.curated/security-threat-model/references/security-controls-and-assets.md) (secrets, build artifacts, isolation, supply chain, change control).

**Caveat for us:** Phrasing is AppSec/product. **Inference:** keep the workflow; rewrite entry-point search seeds and risk examples for Host/Guest, volumes, shell control plane, Quadlets, IAM, agent instruction files.

**Confidence:** High — SKILL + prompt-template + controls reference read from primary GitHub.

### 2. Anthropic `/threat-model` (defending-code-reference-harness) — Gold

**Why steal it:** First-party Anthropic skill that *defines* construction-soundness vs vuln hunting, with interview (owner) and bootstrap (code) modes writing one schema. Lives beside `vuln-scan` / `triage` in the same harness — intentional pipeline separation ([skill tree](https://github.com/anthropics/defending-code-reference-harness/tree/main/.claude/skills)).

**Litmus test (paraphrase):** If patching one line makes an entry disappear, it was a vulnerability, not a threat. Threats stand after known bugs are fixed; vulns appear only as **evidence** raising likelihood ([SKILL.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/SKILL.md)).

**Modes:**

| Mode | Needs | Method |
| --- | --- | --- |
| `interview` | Application owner present | Shostack 4Q conversational fill of schema |
| `bootstrap` | Local checkout (± past vulns) | Research swarm → synthesize → generalize vulns to threat classes → STRIDE gap-fill → emit |
| `bootstrap-then-interview` | Both | Code-grounded draft, then owner refinement |

**Stealable pieces:**

- **Fixed output contract** ([schema.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/schema.md)): System context; Assets; Entry points & trust boundaries; Threats table (`actor`, `surface`, `asset`, `impact`, `likelihood`, `status`, `controls`, `evidence`); Deprioritized; Open questions; Provenance; Recommended mitigations (class-level, not per-bug patches).
- **Actor enum** includes `supply_chain` and `insider` — relevant to CI and Host operators.
- **Bootstrap Infra reader** ([bootstrap.md](https://github.com/anthropics/defending-code-reference-harness/blob/main/.claude/skills/threat-model/bootstrap.md)): Terraform, k8s manifests, Dockerfiles, CI workflows, IAM/service-account files — identities, grants, credentials that survive teardown. **Best primary-source match to Propraetor’s construction concerns among Gold skills.**
- **Surface mapper** includes lockfiles, vendored deps, `curl | sh` in build scripts.
- **Safety preamble:** static analysis only; decline exploit validation (point to vuln pipeline).
- **Completion:** all schema sections written; top 5 threats by L×I printed; open questions left for owner (bootstrap) or unverified owner claims (interview).

**Caveat:** Tied to Anthropic harness tooling (`checkpoint.py`, Task subagents). **Inference:** steal schema + modes + infra swarm briefs; simplify checkpointing for a Propraetor skill.

**Confidence:** High — SKILL, schema, bootstrap primary files read.

### 3. Bitwarden `threat-modeling` + `reviewing-security-architecture` — Recommended

**Why steal it:** Rare public eng-org skills that encode **who does what** (engineering Phase 1 vs AppSec Phase 2–4), **ADR alignment**, and a disciplined Security Definition format that forces attacker capabilities *and* limitations ([threat-modeling SKILL](https://github.com/bitwarden/ai-plugins/blob/main/plugins/bitwarden-security-engineer/skills/threat-modeling/SKILL.md)).

**Stealable pieces:**

- **Engagement model:** DFD + security requirements + SDs + STRIDE locally; escalate for greenfield, new IPC, data-sharing, cross-domain — pattern for Propraetor “when Host/Guest boundary changes, re-model.”
- **Security Definition triad:** threat model (can/cannot) + security goals (testable guarantees with principle/asset/harm rationale) + accepted goal status (met / partial / not met / best effort).
- **Anti-noise rules:** prune dominated threats; prefer 3–5 load-bearing SDs; verbosity is failure; quantify “brief exposure.”
- **Architecture skill:** validate every trust-boundary crossing (validate, authenticate, authorize, sanitize, log); fail closed; least privilege; feed findings into TM ([architecture SKILL](https://github.com/bitwarden/ai-plugins/blob/main/plugins/bitwarden-security-engineer/skills/reviewing-security-architecture/SKILL.md)).
- **Templates:** SD document, Mermaid DFD, threat catalog under `examples/`.

**Caveat:** Vault/crypto/web token focus. Ownership is **team AppSec escalation**, not per-surface RACI. Still the strongest *accountability process* among public skills.

**Confidence:** High for both SKILL.md files.

### 4. GitHub awesome-copilot `threat-model-analyst` — Interesting (steal heavily; gate A)

**Why note it:** Most elaborate open STRIDE-A report factory: architecture overview, Mermaid DFDs, element/flow/boundary tables, STRIDE-A per component, findings with CVSS 4.0, `threat-inventory.json`, incremental refresh ([orchestrator](https://github.com/github/awesome-copilot/blob/main/skills/threat-model-analyst/references/orchestrator.md)).

**Stealable pieces:**

- Progressive disclosure (orchestrator → skeletons → verification sub-agent).
- **Deployment classification** binding exploitability (e.g. localhost vs exposed) — useful anti-inflation for Host-local tools.
- Incremental mode: new / resolved / still-present threats — living model hygiene.
- Sub-agent governance (parent owns writes) — operational lesson for long TM runs.

**Caveat:** Community content on `github/awesome-copilot` → **Medium** credibility; 34 mandatory rules risk cargo-cult overkill for Propraetor. Also noted as Interesting (not Gold) in the prior security-review note.

**Confidence:** High for SKILL + orchestrator primary reads.

### 5. Trail of Bits `audit-context-building` — Recommended precursor

**Why steal it:** Explicit **non-vuln** phase that builds invariants, workflows, and trust boundaries before hunting ([SKILL.md](https://github.com/trailofbits/skills/blob/main/plugins/audit-context-building/skills/audit-context-building/SKILL.md)). Phase 3 includes trust-boundary mapping and fragility clustering. Completeness checklist + anti-rationalization table.

**Inference:** Pair as Stage 0 before OpenAI/Anthropic-style threat enumeration — same role Anthropic’s research swarm plays inside bootstrap.

**Confidence:** High.

### 6. OWASP Attack Surface Analysis + Threat Modeling Cheat Sheets — Recommended substrates

**Attack Surface Analysis** ([primary](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html)):

- Surface = entry/exit paths + protecting code + valuable data + protecting code for that data, overlaid with roles (esp. anonymous vs highly privileged).
- **Bucket and count** types of attack points (don’t inventory every endpoint); notice when a *new type* appears → trigger threat assessment.
- Change triggers: auth/session, authZ roles, crypto, validation architecture, trust relationships, new user types.
- Links recursively to threat modeling; mentions Relative Attack Surface Quotient (Microsoft/Howard lineage).

**Threat Modeling Cheat Sheet** ([primary](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)):

- 4Q → system modeling (DFDs) → STRIDE (or PASTA/OCTAVE) → mitigate/eliminate/transfer/accept → stakeholder validation.
- Cloud note: shared responsibility, IAM, IaC, containers — maps to Propraetor Host vs Guest.

**Confidence:** High.

### 7. Microsoft SDL / Secure by Design + hve-core SBD-08 — Recommended substrates

- **SDL five steps:** requirements → diagram → identify threats → mitigate → validate ([SDL](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling)).
- **STRIDE** as element-oriented prompt set; Secure by Design stresses “thinking like an attacker” beyond checklist STRIDE ([Secure by Design](https://www.microsoft.com/en-us/securityengineering/sdl/practices/secure-by-design)).
- **SBD-08 Minimize Attack Surface** checklist: only necessary services/ports; remove defaults/samples; least privilege; segment trust levels; document intended surface and validate against deployed state ([08-minimize-attack-surface.md](https://github.com/microsoft/hve-core/blob/main/.github/skills/security/secure-by-design/references/08-minimize-attack-surface.md)). UK NCSC + ASD ACSC provenance via Microsoft packaging.

**Confidence:** High.

### 8. NIST SSDF PW.1 / PO.2 + SP 800-154 + CISA Secure by Design — Recommended framing / ownership

- **PW.1:** use threat modeling, attack modeling, or **attack surface mapping** to assess software security risk; track responses ([SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final)).
- **PO.2:** define SDLC roles and responsibilities; example: designate code owners — institutional hook for **surface ownership**.
- **SP 800-154 (draft):** identify/characterize system & data → select attack vectors → characterize controls → analyze ([CSRC](https://csrc.nist.gov/pubs/sp/800/154/ipd)).
- **CISA Secure by Design:** technology providers take ownership of security outcomes; use tailored threat models during product design ([cisa.gov/securebydesign](https://www.cisa.gov/securebydesign)).

**Inference:** These justify putting an **owner column** (or RACI) on Propraetor’s surface inventory even though Gold skills mostly only *ask* the user who owns the service.

**Confidence:** High for SSDF/CISA; High that 800-154 remains draft (IPD).

### Adjacent: Google Mantis, AWS Security Agent, PASTA, ATT&CK

- **Mantis** ([SKILL](https://github.com/google/mantis/blob/main/mantis-threat-model/SKILL.md)): KB-only threat model stage — trust boundaries, actors, high-risk assets, fail-closed Production vs Sample intent checklist, snapshot provenance. Steal *living model + staging*; not usable alone without architecture/entity KB.
- **AWS skill:** thin CLI wrapper around managed STRIDE threat-model jobs — Interesting product pattern, weak portable methodology.
- **PASTA:** 7-stage business-risk methodology ([VerSprite](https://versprite.com/cybersecurity-listings/devsecops/pasta-threat-modeling/)) — steal stage order for heavy assessments; not an agent skill.
- **ATT&CK:** technique vocabulary to tag Host/CI/supply-chain actor capabilities once surfaces exist.

---

## Convergent methodology pattern (threat-profile / construction soundness)

Across Gold and Recommended sources, a skill-worthy *threat-profile* assessment converges on:

| Stage | What credible sources do |
| --- | --- |
| Frame | Shostack/Manifesto 4Q or SDL 5 steps; declare system vs change scope (whole architecture / component) |
| Model | Components, data stores, actors; DFD or equivalent; **trust boundaries as first-class edges** (OpenAI, OWASP, Bitwarden, Microsoft) |
| Inventory surfaces | Entry/exit points, channels, privilege roles; bucket by type; separate runtime vs CI/dev (OpenAI, OWASP ASA, Anthropic surface mapper) |
| Assets | What must not leak/alter/stop — data, credentials, integrity-critical state, build artifacts (OpenAI, Anthropic schema, NIST 800-154 data-centric) |
| Adversary | Capabilities **and** non-capabilities / limitations (OpenAI, Bitwarden SDs); optional ATT&CK tags |
| Enumerate | Abuse paths or STRIDE(-A) classes that **survive individual patches** (Anthropic litmus); keep set small and high-signal (OpenAI, Bitwarden) |
| Prioritize | Explicit likelihood × impact; status (unmitigated / partial / accepted); existing controls with evidence |
| Own | Solicit service/system owner; escalate when boundaries change; ideally assign **accountable owner per surface/control** (gap — see below; NIST PO.2 / CISA / Bitwarden engagement) |
| Reduce | Document intended surface; remove unnecessary types (OWASP ASA, SBD-08) |
| Emit | Living Markdown (+ optional Mermaid, inventory JSON); open questions; class-level mitigations; focus paths for later vuln review |
| Done when | Entry points & boundaries covered; assumptions explicit; schema/checklist satisfied; owner feedback reflected or parked (OpenAI Q8, Anthropic schema, OWASP validate question) |
| Disclosure | Thin SKILL + progressive refs/skeletons (OpenAI, Anthropic, Bitwarden, awesome-copilot) |

---

## Gaps for Propraetor

No Gold artifact is a drop-in **infra construction-soundness** skill. Specific gaps:

1. **Host vs Guest trust boundary** as a first-class taxonomy. Skills speak “client/API/DB”; Propraetor needs Host control plane vs Guest workloads, volume mounts, and privilege boundaries called out by name.
2. **Volumes / bind mounts / state directories as assets and surfaces.** OWASP ASA mentions files and backups; Anthropic infra reader is closest; still no durable “writable mount = Host write” surface type in public skills.
3. **Shell as control plane.** Entry-point tables skew HTTP/API; Anthropic bootstrap seeds are language-agnostic but not shell-orchestrator-specific. Prior vuln-review research showed Anthropic *diff* review actively soft-pedals shell — do not import that bias into threat modeling.
4. **Ownership / RACI of surfaces.** Gold skills ask “who owns the service?” once; almost none require a table: surface → control → **Accountable** human/team (CI trigger owner, secret owner, volume owner, Quadlet owner). Need to invent from NIST PO.2 + Bitwarden engagement + CISA producer-ownership language.
5. **Agent skills / instruction files as attack surface.** Sentry GHA skill (prior note) covers `AGENTS.md` / `CLAUDE.md` poisoning for *CI*; threat-profile skills rarely list agent instruction packs, skill installs, or MCP configs as entry points — Propraetor should.
6. **Pre-stability / no-compat construction.** External TM skills assume stable public APIs; none discuss security implications of deliberate breaking renames (dual-read of trust paths). Domain-specific.
7. **skills.sh noise.** “PASTA” and “attack surface” queries return geoscience, Azure EASM product ops, and pentest recon — easy to confuse with construction-soundness methodology.

**Inference:** Design a Propraetor skill as **OpenAI workflow + Anthropic schema/litmus/infra swarm + OWASP surface bucketing + Bitwarden ownership/escalation hooks + SBD-08 reduction checklist**, with a **custom surface taxonomy** (Host, Guest, volume, secret, IAM principal, CI trigger, agent instruction, supply chain) and an **owner column** mandatory in the inventory.

---

## Ranked shortlist (inspiration)

1. **OpenAI `security-threat-model` (+ ToB curated redistrib)** — portable process, evidence rules, owner pause, output contract  
2. **Anthropic `/threat-model` (defending-code-reference-harness)** — threat≠vuln litmus, schema, interview/bootstrap, infra/supply-chain swarm  
3. **Bitwarden `threat-modeling` + `reviewing-security-architecture`** — engagement ownership, SD triad, trust-boundary review  
4. **OWASP Attack Surface Analysis + Threat Modeling Cheat Sheets** — surface inventory + 4Q/STRIDE substrate  
5. **Trail of Bits `audit-context-building`** — precursor system comprehension (non-vuln)  
6. **Microsoft SDL STRIDE/5-step + hve-core SBD-08** — diagram/mitigate/validate + surface minimization checklist  
7. **NIST SSDF PW.1 + PO.2 (+ CISA Secure by Design)** — organizational framing and ownership mandate  
8. **GitHub awesome-copilot `threat-model-analyst`** — steal DFD/incremental/verification machinery; Medium credibility  
9. **Google Mantis `mantis-threat-model`** — living KB-staged model + deployment-intent discipline  
10. **ToB `supply-chain-risk-auditor`** — companion for one critical Propraetor surface  

Explicit **non-goals for this skill class:** ToB `differential-review`, Anthropic `/security-review`, Cursor Find-vulnerabilities, Sentry `security-review` — use those for PR/diff hunting after the threat profile says where to look ([prior research](./security-review-agent-skills.md)).

---

## Claims confidence summary

| Area | Confidence |
| --- | --- |
| OpenAI / Anthropic / Bitwarden / Mantis / AWS / ToB audit-context primary skill texts | High — fetched from owning GitHub |
| OWASP cheat sheets, Manifesto, Microsoft SDL pages, CISA hub | High |
| NIST SP 800-218 PW.1/PO.2 | High (PDF text) |
| NIST SP 800-154 | High content; note **draft/IPD** status |
| awesome-copilot threat-model-analyst | High for artifact shape; Medium for institutional authority |
| PASTA stage list | High via VerSprite primary pages; book not re-read cover-to-cover this session |
| skills.sh install counts | Medium — snapshot at research time (~2026-08-04) |
| “No Gold skill ships full RACI for surfaces” | **Inference** High from surveyed set; not a proof of global absence |
