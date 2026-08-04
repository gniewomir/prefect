# Threat modeling and security vocabulary — learning roadmap

**Researched:** 2026-08-04  
**Question:** What is the commonly accepted vocabulary for threat modeling and adjacent security / risk concepts, grounded in primary standards and first-party frameworks, arranged as a learning roadmap?  
**Scope:** Widely used terms and named methodologies (STRIDE, PASTA, LINDDUN, Attack Trees, OCTAVE, Trike, Manifesto / Four Questions, ATT&CK, CAPEC, CWE/CVE, CVSS, etc.). Prefer NIST, ISO/IEC public descriptions, OWASP, MITRE, Microsoft SDL, FIRST, CISA, Lockheed Martin Kill Chain, SEI OCTAVE. Not an exhaustive niche encyclopedia; vendor-only jargon omitted or flagged.  
**Method:** Primary sources only (official glossaries, specs, first-party methodology pages). Claims cite owning URLs or document IDs. Definitions paraphrase or quote those sources; invent nothing. Terms that could not be grounded appear in **Gaps**.

---

## How to read this map

Related clusters build on each other:

```text
Information security / risk (foundations)
    → CIA (+ authenticity, accountability)
        → Asset · Threat · Vulnerability · Likelihood · Impact · Risk
            → Threat modeling as discipline
                → System model primitives (DFD, trust boundary, entry points)
                    → Threat taxonomies & methodologies
                        → Adversary / campaign language (TTP, Kill Chain, ATT&CK)
                            → Weakness & vuln identifiers (CWE, CVE, CAPEC, CVSS)
                                → Controls & residual risk
                                    → Adjacent architecture (attack surface, zero trust, secure by design)
```

**Core relationship (risk equation):** A **threat** may exploit a **vulnerability** affecting an **asset**; **risk** is typically a function of **likelihood** and **impact** ([NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf); [NIST CSRC glossary — risk](https://csrc.nist.gov/glossary/term/risk)).

---

## 1. Foundations — information security, risk, assurance

### Information security

Protection of information and information systems from unauthorized access, use, disclosure, disruption, modification, or destruction in order to provide **confidentiality**, **integrity**, and **availability** ([NIST CSRC — information security](https://csrc.nist.gov/glossary/term/information_security), from 44 U.S.C. / FIPS 200 lineage).

*Why it matters:* Threat modeling sits inside this goal: designs are analyzed so CIA (and related properties) are not lost to adversarial or accidental events.

### Risk (information security risk)

A measure of the extent to which an entity is threatened by a potential circumstance or event, typically a function of (i) adverse **impacts** if it occurs and (ii) **likelihood** of occurrence ([NIST CSRC — risk](https://csrc.nist.gov/glossary/term/risk); [NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf)). Information-system-related security risks arise from loss of confidentiality, integrity, or availability and consider impacts to operations, assets, individuals, other organizations, and the Nation ([NIST CSRC — information system-related security risks](https://csrc.nist.gov/glossary/term/information_system_related_security_risks)).

*Why it matters:* Threat models feed risk decisions; they are not a substitute for organizational risk framing ([NIST SP 800-39](https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-39.pdf)).

### Risk assessment

Process of identifying, estimating, and prioritizing information security risks — analyzing threat and vulnerability information to determine extent of adverse impact and likelihood ([NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf)).

### Assurance

Grounds for justified confidence that a security (or privacy) claim has been or will be achieved; typically obtained via techniques that generate credible evidence ([NIST CSRC — assurance](https://csrc.nist.gov/glossary/term/assurance), citing ISO/IEC 15026-1 adapted in NIST SP 800-53 / 800-37). Older NIST wording: measure of confidence that security features, practices, procedures, and architecture mediate and enforce security policy ([NIST SP 800-39](https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-39.pdf) via glossary).

*Why it matters:* Threat modeling produces claims (“these threats are mitigated”); assurance asks for evidence those claims hold.

### ISO/IEC 27000 family (ISMS vocabulary / overview)

ISO/IEC 27000 provides overview, concepts, and principles for information security management systems (ISMS) and relates them to ISO/IEC 27001 and sibling standards ([ISO — ISO/IEC 27000](https://www.iso.org/standard/27000); [ISO/IEC 27000:2018 overview and vocabulary](https://www.iso.org/standard/73906.html)). Full normative definitions sit behind ISO paywalls; use NIST glossaries for free operational definitions, and ISO 27000-series for management-system alignment.

---

## 2. Core triad and extensions

### Confidentiality · Integrity · Availability (CIA)

| Property | Definition (NIST lineage) | Source |
| --- | --- | --- |
| **Confidentiality** | Preserving authorized restrictions on information access and disclosure, including means for protecting personal privacy and proprietary information | [NIST CSRC — confidentiality](https://csrc.nist.gov/glossary/term/confidentiality) |
| **Integrity** | Guarding against improper information modification or destruction; includes ensuring information non-repudiation and authenticity | [NIST CSRC — integrity](https://csrc.nist.gov/glossary/term/integrity) |
| **Availability** | Ensuring timely and reliable access to and use of information | [NIST CSRC — availability](https://csrc.nist.gov/glossary/term/availability) |

*Relationship to STRIDE:* Microsoft maps STRIDE categories to desirable attributes (authentication, integrity, non-repudiation, confidentiality, availability, authorization) ([Microsoft Learn — STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats); [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)).

### Authenticity

Property of being genuine and able to be verified and trusted; confidence in the validity of a transmission, message, or message originator ([NIST CSRC — authenticity](https://csrc.nist.gov/glossary/term/authenticity)). Also: property that data originated from its purported source (cryptographic usage in NIST SP 800-38\* series, same glossary page).

### Accountability

Security goal that actions of an entity can be traced uniquely to that entity — supports non-repudiation, deterrence, fault isolation, intrusion detection/prevention, and after-action recovery ([NIST CSRC — accountability](https://csrc.nist.gov/glossary/term/accountability), NIST SP 800-12 Rev. 1).

### Privacy (threat-modeling discourse)

Privacy is treated as a first-class modeling target alongside security in the [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/) and in **LINDDUN** privacy threat types ([linddun.org](https://linddun.org/)). Not a substitute for CIA; often analyzed with the same Four Questions.

---

## 3. Risk vocabulary

### Asset

Item of value to stakeholders — tangible (hardware, platforms, devices) or intangible (data, software, capability, reputation, IP) ([NIST CSRC — asset](https://csrc.nist.gov/glossary/term/asset), NIST SP 800-160 Vol. 2 Rev. 1). Simpler: anything of value to a person or organization (ISO/IEC/IEEE 24765 cited on same page).

*Relationship:* Assets are what threats harm; attack surface and DFDs make asset/data stores visible.

### Threat

Any circumstance or event with the potential to adversely impact organizational operations, assets, individuals, other organizations, or the Nation through a system via unauthorized access, destruction, disclosure, modification of information, and/or denial of service ([NIST CSRC — threat](https://csrc.nist.gov/glossary/term/threat); [NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf)). Threat events are caused by **threat sources** (adversarial, accidental, structural, environmental) ([SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf)).

### Vulnerability

Weakness in an information system, system security procedures, internal controls, or implementation that could be exploited or triggered by a threat source ([NIST CSRC — vulnerability](https://csrc.nist.gov/glossary/term/vulnerability)).

### Predisposing condition

Condition that exists within an organization, mission/business process, architecture, or information system that affects (increases or decreases) the likelihood that threat events, once initiated, result in adverse impacts ([NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf)).

### Likelihood (of occurrence)

Weighted factor based on subjective analysis of the probability that a given threat is capable of exploiting a given vulnerability or set of vulnerabilities ([NIST CSRC — likelihood of occurrence](https://csrc.nist.gov/glossary/term/likelihood_of_occurrence)).

### Impact

Adverse effect / magnitude of harm to organizational operations and assets, individuals, other organizations, or the Nation if a threat event occurs ([NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf) — risk determination appendices).

### Risk (restated relationally)

**Threat × Vulnerability × Context → Likelihood × Impact → Risk.** A vulnerability without a credible threat path, or a threat with no impactful asset, does not yield meaningful risk in this framing ([SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf)).

### Residual risk

Portion of risk remaining after security measures / controls / countermeasures have been applied ([NIST CSRC — residual risk](https://csrc.nist.gov/glossary/term/residual_risk)).

### Risk appetite

Types and amount of risk, on a broad level, an organization is willing to accept in pursuit of value ([NIST CSRC — Risk Appetite](https://csrc.nist.gov/glossary/term/risk_appetite), from COSO / NISTIR 8286 lineage).

### Risk tolerance

Level of risk or degree of uncertainty acceptable to an organization; readiness to bear remaining risk after risk response to achieve objectives ([NIST CSRC — risk tolerance](https://csrc.nist.gov/glossary/term/risk_tolerance)).

*Appetite vs tolerance:* Appetite is broad willingness; tolerance is acceptable variance / remaining risk after treatment (same NIST glossary pages). Threat-model “accept” decisions should align with both.

---

## 4. Threat modeling as a discipline

### Definition (Manifesto)

**Threat modeling** is analyzing representations of a system to highlight concerns about security and privacy characteristics ([Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/)).

### Definition (OWASP)

In application security, a structured, repeatable process: model a system from a security perspective, identify applicable threats, determine responses; analyze from an adversarial perspective ([OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)).

### Definition (Microsoft SDL)

Engineering technique to identify threats, attacks, vulnerabilities, and countermeasures that could affect an application; shapes design, meets security objectives, reduces risk ([Microsoft SDL — Threat Modeling](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling)).

### Four key questions (Shostack / Manifesto)

1. What are we working on?  
2. What can go wrong?  
3. What are we going to do about it?  
4. Did we do a good enough job?  

([Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/); frame also at [adamshostack/4QuestionFrame](https://github.com/adamshostack/4QuestionFrame); restated by [OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html) and [LINDDUN](https://linddun.org/)).

### Microsoft SDL five steps

1. Defining security requirements  
2. Creating an application diagram  
3. Identifying threats  
4. Mitigating threats  
5. Validating that threats have been mitigated  

([Microsoft SDL — Threat Modeling](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling)).

### Manifesto values (compressed)

Prefer: culture of finding/fixing design issues; people and collaboration; journey of understanding; doing threat modeling; continuous refinement — over checkbox compliance, tool fetishism, one-shot snapshots ([Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/)).

### When used

Ideally early in the SDLC (design) and maintained as the system changes ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html); Manifesto principle of early and frequent analysis). NIST SSDF practice **PW.1** calls for designing software to meet security requirements and mitigate identified security risks ([NIST SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final)).

### NIST SP 800-154 (data-centric threat modeling)

Draft NIST guide: threat modeling is a form of **risk assessment** that models attack and defense aspects of a logical entity (data, application, host, system, or environment). **Data-centric** system threat modeling focuses on protecting particular types of data within systems; the draft defines fundamental principles for that style of modeling rather than replacing named methodologies ([NIST SP 800-154 IPD](https://csrc.nist.gov/pubs/sp/800/154/ipd); NIST planning note indicates intent to finalize).

There is **no single universally accepted industry standard** process ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)).

---

## 5. Modeling primitives

### System model / representation

Any diagram or description used to answer “what are we working on?” — DFDs are the most common ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html); Microsoft Threat Modeling Tool uses standard notation for components, data flows, and security boundaries ([Microsoft SDL](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling))).

### Data Flow Diagram (DFD)

Visual model of a system and its interactions with data and other entities, using a small set of symbols; should show **trust boundaries**, **data flows**, **data stores**, **processes**, and **external entities** ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)). Trike’s implementation model likewise uses DFDs ([Trike v1 Methodology Document](https://trike.sourceforge.net/papers/Trike_v1_Methodology_Document-draft.pdf)).

### Trust boundary / security boundary

Boundary across which trust assumptions change (e.g., Internet → DMZ → app → data store). OWASP requires DFDs to make trust boundaries clear because they often represent attack points ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)). Microsoft tool documentation emphasizes visualizing **security boundaries** with components and data flows ([Microsoft SDL](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling)).

*Relationship:* Crossing a trust boundary without commensurate controls is a classic threat-model finding; related to zero trust’s rejection of location-as-trust ([NIST SP 800-207](https://csrc.nist.gov/pubs/sp/800/207/final)).

### Entry / exit points (attack points)

Paths for data/commands into and out of the application — UI fields, HTTP headers/cookies, APIs, files, databases, messages, runtime arguments, etc. ([OWASP Attack Surface Analysis Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html)).

### External entity · Process · Data store · Data flow

Standard DFD element types used when applying STRIDE-per-element ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html); [Microsoft Learn — STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)).

### Actor (Trike / modeling)

In Trike, actors participate in an **actor–asset–action** matrix defining allowed/disallowed CRUD-style actions ([Trike v1 Methodology Document](https://trike.sourceforge.net/papers/Trike_v1_Methodology_Document-draft.pdf)). Distinct from **threat actor** (adversary vocabulary, §7).

---

## 6. Threat taxonomies and methodologies

Named vocabularies — what they are and when they fit.

### STRIDE (Microsoft)

Mnemonic threat categories for design analysis:

| Category | Microsoft description (abbrev.) | Typical property violated |
| --- | --- | --- |
| **S**poofing | Illegally accessing/using another’s authentication information | Authentication |
| **T**ampering | Malicious modification of data at rest or in transit | Integrity |
| **R**epudiation | Denying actions without proof otherwise | Non-repudiation / accounting |
| **I**nformation Disclosure | Exposure of information to unauthorized parties | Confidentiality |
| **D**enial of Service | Denying service to valid users | Availability |
| **E**levation of Privilege | Gaining unauthorized privileged access | Authorization |

([Microsoft Learn — Threats / STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats); [OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)).

*When:* Default software-centric elicitation prompt set; pairs with DFDs (STRIDE-per-element). Not a full risk methodology by itself.

### DREAD (historical Microsoft prioritization)

Scoring criteria used in some Microsoft materials (e.g., driver threat modeling): **D**amage, **R**eproducibility, **E**xploitability, **A**ffected users, **D**iscoverability — often averaged for priority ([Microsoft Learn — Threat modeling for drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/driversecurity/threat-modeling-for-drivers)). Treat as historical/optional ranking vocabulary, not current SDL mandatory process (SDL pages emphasize STRIDE + mitigation validation, not DREAD).

### PASTA (Process for Attack Simulation and Threat Analysis)

Risk-centric, seven-stage methodology documented by Tony UcedaVélez and Marco M. Morana in *Risk Centric Threat Modeling* (Wiley) and described by the co-creator’s firm: stages typically **Define Objectives → Technical Scope → Application Decomposition → Threat Analysis → Vulnerability/Weakness Analysis → Attack Modeling → Risk and Impact Analysis** ([Wiley book page](https://www.wiley.com/en-us/Risk+Centric+Threat+Modeling%3A+Process+for+Attack+Simulation+and+Threat+Analysis-p-9780470500965); [VerSprite PASTA overview](https://versprite.com/resources/security/process-for-attack-simulation-and-threat-analysis-pasta-risk-centric-threat-models/); mentioned as alternative process by [OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)).

*When:* Organizations that need business-impact-aligned, attack-simulation-heavy analysis beyond STRIDE brainstorming.

### LINDDUN (KU Leuven)

Privacy threat modeling framework; acronym: **L**inking, **I**dentifying, **N**on-repudiation, **D**etecting, **D**ata Disclosure, **U**nawareness, **N**on-compliance ([linddun.org](https://linddun.org/); threat trees at [linddun.org/threat-trees](https://linddun.org/threat-trees/)). Methods: GO (lean cards), PRO (DFD/systematic), MAESTRO (enriched models) ([linddun.org/methods](https://linddun.org/methods/)). Explicitly STRIDE-compatible for parallel security+privacy modeling ([linddun.org](https://linddun.org/)).

*When:* Personal data / privacy-by-design analysis.

### Attack trees

Hierarchical description of how an attacker could realize a specific threat: root = goal; children = ways to achieve that goal (OR = alternatives; AND = required conjunction of subgoals). Schneier’s canonical pedagogy: formal, methodical modeling of system security via attack trees; leaf values (Boolean or continuous: cost, skill, legality, …) propagate to the goal so defenders can rank paths and test countermeasures ([Bruce Schneier — Attack Trees](https://www.schneier.com/academic/archives/1999/12/attack_trees.html), *Dr. Dobb’s Journal*, Dec 1999). Trike uses the same structure in its methodology ([Trike v1 Methodology Document](https://trike.sourceforge.net/papers/Trike_v1_Methodology_Document-draft.pdf) §3.2). CAPEC notes attack trees among complementary tools with attack patterns ([CAPEC — About](https://capec.mitre.org/about/index.html)).

*When:* Deepening a single high-value threat into paths; PASTA Stage 6 and Trike both use them.

### OCTAVE / OCTAVE Allegro (CERT/SEI)

**OCTAVE** = Operationally Critical Threat, Asset, and Vulnerability Evaluation. **OCTAVE Allegro** streamlines information security risk assessment focusing on information assets, containers (people, technology, facilities), threats, and business impact — documented in CMU/SEI-2007-TR-012 ([SEI library entry](https://www.sei.cmu.edu/library/introducing-octave-allegro-improving-the-information-security-risk-assessment-process/); [PDF](https://insights.sei.cmu.edu/documents/786/2007_005_001_14885.pdf)).

*When:* Organizational / information-asset risk workshops more than component STRIDE.

### Trike

Open-source, risk-management-oriented threat modeling methodology: requirements model (actor–asset–action matrix) + implementation model (DFDs) → automated-friendly threat generation, attack trees/graphs, weaknesses, vulnerabilities, mitigations ([Trike project](https://trike.sourceforge.net/); [Trike v1 Methodology Document](https://trike.sourceforge.net/papers/Trike_v1_Methodology_Document-draft.pdf)). Defensive perspective emphasized by authors.

*When:* Formal, audit-oriented modeling with explicit risk linkage.

### Threat Modeling Manifesto / Capabilities

Shared values, principles, patterns, and anti-patterns; methodology-agnostic ([threatmodelingmanifesto.org](https://www.threatmodelingmanifesto.org/); capabilities extension at [threatmodelingmanifesto.org/capabilities](https://www.threatmodelingmanifesto.org/capabilities/)).

### Relationship summary

| Approach | Primary lens | Typical input |
| --- | --- | --- |
| STRIDE | Threat *categories* | DFD elements |
| LINDDUN | Privacy threat *types* | DFD / cards |
| Attack trees | Attack *paths* to a goal | Single threat/goal |
| PASTA | Risk + attack *simulation* | Business + tech scope |
| OCTAVE Allegro | Operational *info-asset* risk | Assets & containers |
| Trike | Defensive *audit* + risk | Actor matrix + DFD |
| Manifesto 4Q | Process *questions* | Any representation |

---

## 7. Adversary and campaign vocabulary

### Threat actor

An individual or a group posing a threat ([NIST CSRC — threat actor](https://csrc.nist.gov/glossary/term/threat_actor), NIST SP 800-150). Related: source of risk that can result in harmful impact ([NIST SP 800-221](https://csrc.nist.gov/glossary/term/threat_actor)).

### Tactics, Techniques, and Procedures (TTP)

Behavior of an actor: **tactic** = highest-level description; **techniques** = more detail in context of a tactic; **procedures** = lower-level, highly detailed description in context of a technique ([NIST CSRC — TTP](https://csrc.nist.gov/glossary/term/tactics_techniques_and_procedures)).

### Indicator of Compromise (IOC)

Technical artifacts or observables that suggest an attack is imminent, underway, or that a compromise may have already occurred ([NIST CSRC — Indicator of Compromise](https://csrc.nist.gov/glossary/term/indicator_of_compromise)).

### Cyber Kill Chain® (Lockheed Martin)

Intelligence-driven defense model identifying what adversaries must complete to achieve objectives; seven steps enhance visibility into TTP ([Lockheed Martin — Cyber Kill Chain](https://www.lockheedmartin.com/en-us/capabilities/cyber/cyber-kill-chain.html)). Classic white paper phases ([LM white paper PDF](https://www.lockheedmartin.com/content/dam/lockheed-martin/rms/documents/cyber/LM-White-Paper-Intel-Driven-Defense.pdf)):

1. Reconnaissance  
2. Weaponization  
3. Delivery  
4. Exploitation  
5. Installation  
6. Command and Control (C2)  
7. Actions on Objectives  

Defender advantage: interrupting any stage breaks the chain ([Gaining the Advantage PDF](https://www.lockheedmartin.com/content/dam/lockheed-martin/rms/documents/cyber/Gaining_the_Advantage_Cyber_Kill_Chain.pdf)).

*Relationship to threat modeling:* Kill Chain / ATT&CK describe *how campaigns unfold*; STRIDE/LINDDUN describe *what can go wrong in a design*. OWASP notes STRIDE pairs with kill chains or ATT&CK ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)).

### MITRE ATT&CK®

Globally accessible knowledge base of adversary **tactics** and **techniques** based on real-world observations; foundation for threat models and methodologies in industry and government ([attack.mitre.org](https://attack.mitre.org/)). Design philosophy: tactics = *why* (adversary tactical objective); techniques/sub-techniques = *how* / *what* ([ATT&CK Design and Philosophy PDF](https://attack.mitre.org/docs/ATTACK_Design_and_Philosophy_March_2020.pdf)). ATT&CK is **not** an exhaustive enumeration of application attack vectors — use CAPEC/CWE for that ([same PDF](https://attack.mitre.org/docs/ATTACK_Design_and_Philosophy_March_2020.pdf); [CAPEC ↔ ATT&CK comparison](https://capec.mitre.org/about/attack_comparison.html)).

### MITRE Engage™

Framework for planning and discussing **adversary engagement** (denial, deception) operations; Engage Matrix of goals, approaches, and activities informed by ATT&CK-observable behavior ([engage.mitre.org](https://engage.mitre.org/); [Engage Matrix](https://engage.mitre.org/learn-more-matrix/)).

### MITRE D3FEND™

Knowledge graph of cybersecurity **countermeasures** (defensive techniques), complementary to offensive catalogs ([d3fend.mitre.org](https://d3fend.mitre.org/)).

---

## 8. Weakness and vulnerability identifiers

### CWE (Common Weakness Enumeration)

Community-developed list of software and hardware **weaknesses**. A weakness is a condition in a software, firmware, hardware, or service component that, under certain circumstances, could contribute to the introduction of vulnerabilities ([cwe.mitre.org — About](https://cwe.mitre.org/about/index.html)).

### CVE (Common Vulnerabilities and Exposures)

CVE Program identifies, defines, and catalogs **publicly disclosed cybersecurity vulnerabilities** — one CVE Record per vulnerability for consistent naming and coordination ([cve.org — Overview](https://www.cve.org/About/Overview)). CVE does **not** assign severity scores (that is CVSS / other systems) — clarified in CVE Program myth-busting on the same site.

### CAPEC (Common Attack Pattern Enumeration and Classification)

Catalog of **attack patterns** — common attributes and approaches adversaries use to exploit known weaknesses; derived from design-pattern thinking applied destructively ([capec.mitre.org](https://capec.mitre.org/); [About CAPEC](https://capec.mitre.org/about/index.html)). Focused on application security / exploit patterns; associated with CWE ([CAPEC ↔ ATT&CK](https://capec.mitre.org/about/attack_comparison.html)).

### Relationship: CWE · CAPEC · CVE · ATT&CK

```text
CWE (weakness type)
  ↑ exploited via
CAPEC (attack pattern)     ATT&CK (operational TTP lifecycle)
  ↑ may yield instance
CVE (specific disclosed vulnerability)
```

([CAPEC About](https://capec.mitre.org/about/index.html); [CWE About](https://cwe.mitre.org/about/index.html); [CAPEC ↔ ATT&CK](https://capec.mitre.org/about/attack_comparison.html)).

### CVSS (Common Vulnerability Scoring System)

FIRST open framework to capture principal characteristics of a vulnerability and produce a numerical severity score (and qualitative rating) ([FIRST CVSS](https://www.first.org/cvss/); [CVSS v4.0 Specification](https://www.first.org/cvss/v4-0/specification-document)). v4.0 metric groups: **Base**, **Threat**, **Environmental**, **Supplemental**. Base reflects intrinsic severity; Threat/Environmental refine for time and consumer environment; Supplemental adds context without changing the score formula ([CVSS v4.0 Spec](https://www.first.org/cvss/v4-0/specification-document)).

*Why it matters in threat modeling:* CVSS ranks *known vulnerabilities*; threat modeling ranks *design threats*. Do not treat a CVSS Base score alone as organizational risk (FIRST notes consumers should enrich with Threat/Environmental and non-CVSS business factors).

---

## 9. Controls and mitigation

### Security control

Safeguard or countermeasure prescribed for an information system or organization to protect confidentiality, integrity, and availability of the system and its information ([NIST CSRC — security control](https://csrc.nist.gov/glossary/term/security_control)).

*Note:* NIST glossary entries treat **safeguard** and **countermeasure** as synonyms inside “security control”; standalone “countermeasure” / “safeguard” glossary URLs were not consistently available — use the security-control definition.

### Mitigation responses (threat modeling)

Shostack-style responses summarized by OWASP: **Mitigate**, **Eliminate**, **Transfer**, **Accept** ([OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)). Align Accept with residual risk vs appetite/tolerance (§3).

### Residual risk

See §3 — risk remaining after measures applied ([NIST CSRC — residual risk](https://csrc.nist.gov/glossary/term/residual_risk)).

### Defense-in-depth

Information security strategy integrating people, technology, and operations capabilities to establish variable barriers across multiple layers and missions of the organization ([NIST CSRC — defense-in-depth](https://csrc.nist.gov/glossary/term/defense_in_depth)). Alternate industrial wording: multiple countermeasures layered so attacks missed by one technology are caught by another (ISA/IEC 62443 cited on same page).

### D3FEND

See §7 — defensive countermeasure knowledge graph ([d3fend.mitre.org](https://d3fend.mitre.org/)).

---

## 10. Adjacent architecture concepts

### Attack surface

**NIST:** Set of points on the boundary of a system, system component, or environment where an attacker can try to enter, cause an effect on, or extract data from that system, component, or environment ([NIST CSRC — attack surface](https://csrc.nist.gov/glossary/term/attack_surface), NIST SP 800-53 Rev. 5).

**OWASP (application):** Sum of paths for data/commands into and out of the application; code protecting those paths; valuable data; code protecting that data — overlaid with user roles ([OWASP Attack Surface Analysis Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html)).

*Relationship to threat modeling:* Recursive — changes to attack surface should trigger threat modeling; threat modeling clarifies the surface ([OWASP Attack Surface Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html)). Assets ≠ attack surface: assets are valued things; surface is where interaction/attack is possible.

### Zero trust (high level)

Collection of concepts designed to minimize uncertainty in enforcing accurate, least-privilege **per-request** access decisions, assuming a network that may be compromised ([NIST CSRC — Zero Trust](https://csrc.nist.gov/glossary/term/zero_trust); [NIST SP 800-207](https://csrc.nist.gov/pubs/sp/800/207/final)). No implicit trust based solely on physical/network location or asset ownership; authentication and authorization before sessions to resources; focus on protecting **resources**, not network segments ([SP 800-207 abstract](https://csrc.nist.gov/pubs/sp/800/207/final)).

*In threat-modeling discourse:* Challenges “inside the perimeter = trusted” assumptions that DFDs sometimes encode as coarse trust zones.

### Secure by Design (CISA)

Products prioritize customer security as a core business requirement in the design phase, decreasing exploitable flaws before market; out-of-the-box secure defaults (e.g., MFA, logging, SSO without extra cost) ([CISA — Secure by Design](https://www.cisa.gov/securebydesign)). Threat modeling is a practical means toward that goal (Manifesto authors’ framing in related commentary; process still Manifesto/OWASP/Microsoft as above).

---

## 11. Suggested study path

Ordered reading aligned to this document’s sections:

| Step | Focus | Primary reads |
| --- | --- | --- |
| 1 | Foundations | [NIST information security](https://csrc.nist.gov/glossary/term/information_security), [risk](https://csrc.nist.gov/glossary/term/risk), [assurance](https://csrc.nist.gov/glossary/term/assurance); skim [SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf) Ch. 1–2 |
| 2 | CIA + extensions | [Confidentiality](https://csrc.nist.gov/glossary/term/confidentiality) / [Integrity](https://csrc.nist.gov/glossary/term/integrity) / [Availability](https://csrc.nist.gov/glossary/term/availability); [authenticity](https://csrc.nist.gov/glossary/term/authenticity); [accountability](https://csrc.nist.gov/glossary/term/accountability) |
| 3 | Risk chain | [Threat](https://csrc.nist.gov/glossary/term/threat), [vulnerability](https://csrc.nist.gov/glossary/term/vulnerability), [asset](https://csrc.nist.gov/glossary/term/asset), [likelihood](https://csrc.nist.gov/glossary/term/likelihood_of_occurrence), [residual risk](https://csrc.nist.gov/glossary/term/residual_risk), [risk appetite](https://csrc.nist.gov/glossary/term/risk_appetite), [risk tolerance](https://csrc.nist.gov/glossary/term/risk_tolerance) |
| 4 | Discipline | [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/); [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html); [Microsoft SDL Threat Modeling](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling); skim [NIST SP 800-154 IPD](https://csrc.nist.gov/pubs/sp/800/154/ipd) for NIST’s data-centric framing |
| 5 | Primitives | OWASP DFD/trust-boundary sections; [Attack Surface Analysis Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html) |
| 6 | Methodologies | STRIDE ([Microsoft Learn](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)); [Schneier Attack Trees](https://www.schneier.com/academic/archives/1999/12/attack_trees.html); then pick one deep: [LINDDUN](https://linddun.org/) *or* [PASTA/Wiley](https://www.wiley.com/en-us/Risk+Centric+Threat+Modeling%3A+Process+for+Attack+Simulation+and+Threat+Analysis-p-9780470500965) *or* [OCTAVE Allegro TR](https://insights.sei.cmu.edu/documents/786/2007_005_001_14885.pdf) *or* [Trike](https://trike.sourceforge.net/papers/Trike_v1_Methodology_Document-draft.pdf) |
| 7 | Adversaries | NIST [threat actor](https://csrc.nist.gov/glossary/term/threat_actor) / [TTP](https://csrc.nist.gov/glossary/term/tactics_techniques_and_procedures); [ATT&CK](https://attack.mitre.org/) + [Design Philosophy](https://attack.mitre.org/docs/ATTACK_Design_and_Philosophy_March_2020.pdf); [Kill Chain white paper](https://www.lockheedmartin.com/content/dam/lockheed-martin/rms/documents/cyber/LM-White-Paper-Intel-Driven-Defense.pdf) |
| 8 | Identifiers | [CWE](https://cwe.mitre.org/about/index.html), [CVE](https://www.cve.org/About/Overview), [CAPEC](https://capec.mitre.org/about/index.html), [CVSS v4.0](https://www.first.org/cvss/v4-0/specification-document) |
| 9 | Controls | [Security control](https://csrc.nist.gov/glossary/term/security_control), [defense-in-depth](https://csrc.nist.gov/glossary/term/defense_in_depth), [D3FEND](https://d3fend.mitre.org/), OWASP mitigation section |
| 10 | Architecture | [Attack surface (NIST)](https://csrc.nist.gov/glossary/term/attack_surface), [SP 800-207 Zero Trust](https://csrc.nist.gov/pubs/sp/800/207/final), [CISA Secure by Design](https://www.cisa.gov/securebydesign) |

**Practice loop:** Draw a DFD of a small system → apply STRIDE → rank with likelihood×impact language → pick mitigations → check residual risk against appetite → optionally map one threat to ATT&CK techniques or a CAPEC pattern.

---

## 12. Primary source index and gaps

### Primary source index (key)

| Source | Role |
| --- | --- |
| [NIST CSRC Glossary](https://csrc.nist.gov/glossary/) | Canonical free definitions (threat, vulnerability, risk, CIA, asset, residual risk, attack surface, zero trust, TTP, IOC, …) |
| [NIST SP 800-30 Rev. 1](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-30r1.pdf) | Risk assessment process and factor relationships |
| [NIST SP 800-39](https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-39.pdf) | Organizational risk management framing |
| [NIST SP 800-207](https://csrc.nist.gov/pubs/sp/800/207/final) | Zero trust architecture |
| [NIST SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final) | SSDF (secure software development; PW.1 context) |
| [NIST SP 800-154 IPD](https://csrc.nist.gov/pubs/sp/800/154/ipd) | Data-centric system threat modeling (draft; NIST intends to finalize) |
| [ISO/IEC 27000](https://www.iso.org/standard/27000) | ISMS overview / vocabulary family |
| [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/) | Discipline definition + Four Questions + values |
| [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html) | Process, STRIDE table, mitigations, DFD guidance |
| [OWASP Attack Surface Analysis Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html) | Attack surface / entry points |
| [Microsoft SDL Threat Modeling](https://www.microsoft.com/en-us/securityengineering/sdl/threatmodeling) | Five steps + tool framing |
| [Microsoft Learn STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) | STRIDE category definitions |
| [LINDDUN](https://linddun.org/) | Privacy threat types and methods |
| [SEI OCTAVE Allegro TR](https://www.sei.cmu.edu/library/introducing-octave-allegro-improving-the-information-security-risk-assessment-process/) | OCTAVE Allegro |
| [Trike methodology PDF](https://trike.sourceforge.net/papers/Trike_v1_Methodology_Document-draft.pdf) | Trike + attack-tree formalization |
| [Schneier — Attack Trees (1999)](https://www.schneier.com/academic/archives/1999/12/attack_trees.html) | Canonical attack-tree pedagogy (AND/OR, leaf valuation) |
| [Wiley PASTA book](https://www.wiley.com/en-us/Risk+Centric+Threat+Modeling%3A+Process+for+Attack+Simulation+and+Threat+Analysis-p-9780470500965) / [VerSprite PASTA](https://versprite.com/resources/security/process-for-attack-simulation-and-threat-analysis-pasta-risk-centric-threat-models/) | PASTA |
| [MITRE ATT&CK](https://attack.mitre.org/) | Tactics/techniques knowledge base |
| [CAPEC](https://capec.mitre.org/) / [CWE](https://cwe.mitre.org/) / [CVE](https://www.cve.org/) | Attack patterns / weaknesses / vulns |
| [FIRST CVSS](https://www.first.org/cvss/) | Severity scoring |
| [Lockheed Martin Cyber Kill Chain](https://www.lockheedmartin.com/en-us/capabilities/cyber/cyber-kill-chain.html) | Intrusion kill chain |
| [MITRE Engage](https://engage.mitre.org/) / [D3FEND](https://d3fend.mitre.org/) | Engagement / defensive countermeasures |
| [CISA Secure by Design](https://www.cisa.gov/securebydesign) | Design-time security ownership |

### Gaps / ungrounded (or weakly grounded)

| Term / topic | Why flagged |
| --- | --- |
| **VAST** (Visual, Agile, and Simple Threat modeling) | Widely cited in secondary comparisons; originated with commercial ThreatModeler tooling. No free first-party methodology specification comparable to Trike/LINDDUN/STRIDE docs was used here — omit as canonical vocabulary until a primary public spec is cited. |
| **“Entry point” as a NIST glossary term** | Practice term from OWASP/Microsoft modeling; not a standalone NIST glossary ID. |
| **“Trust boundary” as a NIST glossary term** | Widely used in SDL/OWASP; [csrc.nist.gov/glossary/term/trust_boundary](https://csrc.nist.gov/glossary/term/trust_boundary) returns 404 (related ideas: security boundaries in SDL tooling, zero trust resource focus in SP 800-207). |
| **Safeguard / countermeasure as standalone NIST terms** | Defined *inside* [security control](https://csrc.nist.gov/glossary/term/security_control); dedicated glossary URLs returned 404 at research time. |
| **ISO/IEC 27000 / 27005 full definitions** | Paywalled standards text; only public ISO overview pages used — prefer NIST for free definitions. |
| **ENISA / NCSC / CIS glossaries** | Not exhaustively mined; no unique canonical term was required that NIST/OWASP/MITRE lacked. |
| **“Threat profile”** | Used in AppSec practice; not a single NIST glossary head term in this research pass. |

---

*End of roadmap. Update this note when glossary URLs or methodology primaries change; prefer nvlpubs/CSRC, owasp.org, mitre.org, first.org, and first-party methodology sites over blog roundups.*
