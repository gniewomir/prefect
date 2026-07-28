# How Cursor Auto chooses a model

**Researched:** 2026-07-28  
**Question:** How does Cursor “Auto” mode determine which underlying model handles a request?  
**Scope:** Cursor IDE / Agent Auto selection, including the Jul 22, 2026 Cursor Router relaunch, legacy Auto / Auto Cost behavior, observability / visibility of the routed model, and plan differences.  
**Method:** Prefer Cursor docs, blog posts, changelogs, and staff replies on the Cursor forum. Where internals are unpublished, include secondary or community claims with an explicit credibility label. Exact routing weights, thresholds, and proprietary classifier code are not public.

### Credibility labels used here

| Label | Meaning |
| --- | --- |
| **High** | Cursor docs, blog, changelog, or Help Center; first-party and current |
| **Medium-High** | Named Cursor staff on the official forum, or first-party blog describing related behavior |
| **Medium** | Older first-party wording that may be superseded, or staff statements that conflict with later docs |
| **Low** | Community experiment / reverse-engineering / unverified local-DB claims |

---

## Verdict

1. **Auto is a router, not a model.** Cursor repeatedly states that Auto selects an underlying model per request rather than binding the chat to one fixed backend ([Cursor Router docs](https://cursor.com/docs/cursor-router) — **High**; [available models help](https://cursor.com/help/models-and-usage/available-models.md) — **High**).
2. **As of 2026-07-22, “Cursor Router” is the relaunched Auto for Teams/Enterprise.** It is described as an ML classifier that routes each agent request by task type and complexity, steered by Cost / Balance / Intelligence modes ([changelog](https://cursor.com/changelog/router) — **High**; [blog](https://cursor.com/blog/router) — **High**; [help](https://cursor.com/help/models-and-usage/cursor-router.md) — **High**).
3. **Cursor does not publish the exact decision algorithm.** Staff have said the exact Auto routing algorithm / model list is not shared ([forum staff reply](https://forum.cursor.com/t/auto-model-mechanism-in-cursor/159697) — **Medium-High**). Even the Router launch describes inputs and goals, not weights or code.
4. **Individual plans currently do not get Cursor Router.** Staff explicitly said Router is Teams/Enterprise only ([forum](https://forum.cursor.com/t/introducing-cursor-router/166386) — **Medium-High**). Individual Auto is therefore closer to the older / Cost-style routing story, which remains less documented.
5. **Documented selection factors cluster around task classification + availability constraints + user/team steering.** Exact priority among those factors is unpublished.
6. **Visibility into the *resolved* Auto model is deliberately limited.** Default UI hides it; the best first-party after-the-fact signal is usage/billing. Hooks and CLI mainly expose the *selected* router label (`Auto` / `default` / `auto-smart`), not the backend that ran. Network interception can capture traffic but is a weak way to learn the routed model. See §5.

---

## 1. Product history that matters

### Pre-Router Auto (through mid-2026)

Older official and staff wording framed Auto as capacity-aware premium routing:

- June 2025 pricing clarification: “Auto automatically routes to different frontier models based on capacity” ([Clarifying our pricing](https://cursor.com/blog/june-2025-pricing) — **High** for that period; partially superseded by later Router docs).
- Forum-cited docs phrase still widely quoted in 2026: Auto selects “the premium model best fit for the immediate task and with the highest reliability based on current demand” ([forum quoting docs](https://forum.cursor.com/t/which-models-used-in-auto-mode/149187) — **Medium**; the live pricing page has changed, so treat the exact URL’d wording as historical).
- Staff (deanrie): Auto picks from models available for the request based on **task type, context, and current model availability and load**; the model can change step to step; exact algorithm is not public ([forum](https://forum.cursor.com/t/auto-model-mechanism-in-cursor/159697) — **Medium-High**).
- Staff (danperks, 2025): Auto routes to a premium model based on multiple factors including **availability and downtime**; the answered model may not be known until the response finishes ([forum](https://forum.cursor.com/t/auto-mode-please-inform-us-which-is-the-exact-model-being-used/96733?page=2) — **Medium-High**, older product era).
- Staff (Colin): Auto picks a model **right before answering each turn**, keeps it for that answer, and may change on later turns based on availability / conditions ([forum](https://forum.cursor.com/t/how-often-does-auto-mode-switch-model/164805) — **Medium-High**).
- Staff (kevinn): Auto also considers **regional availability and load** and will route around a model with availability issues ([forum](https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163) — **Medium-High**).
- Regions docs: when providers restrict models by location, Auto “will choose an available model for each request” ([regions](https://cursor.com/docs/account/regions) — **High**).

### Cursor Router relaunch (2026-07-22)

Cursor renamed/relaunched Auto routing as **Cursor Router**:

- Changelog: Auto is now powered by Cursor Router; per-request classification by task type and complexity; Cost / Balance / Intelligence modes; admin controls; Teams on by default; Enterprise opt-in ([changelog](https://cursor.com/changelog/router) — **High**).
- Help Center: Router is “the relaunched Auto mode”; legacy Auto is now **Cost**; Balance is default for new users; Balance/Intelligence bill at routed-model rates while Cost keeps bundled Auto pricing ([help](https://cursor.com/help/models-and-usage/cursor-router.md) — **High**).
- Docs: Router currently available on Teams and Enterprise ([docs](https://cursor.com/docs/cursor-router) — **High**).
- Staff confirmation: “Cursor Router is currently not available on individual plans!” ([forum](https://forum.cursor.com/t/introducing-cursor-router/166386) — **Medium-High**).

**Inference (Medium):** asking “how Auto works” now requires splitting **Teams/Enterprise Router Auto** from **individual / Cost / legacy Auto**. Collapsing them into one mechanism overclaims.

---

## 2. What Cursor says the router looks at

### Explicitly documented for Cursor Router (Balance / Intelligence)

From first-party Router docs and blog:

| Factor | What Cursor says | Credibility |
| --- | --- | --- |
| Task type / complexity | Classifier routes simple work to fast/efficient models and complex work to frontier models | [docs](https://cursor.com/docs/cursor-router), [help](https://cursor.com/help/models-and-usage/cursor-router.md), [changelog](https://cursor.com/changelog/router) — **High** |
| Query + context + domain | Blog: analyzes query, context, task complexity, and domain, plus learned model strengths | [blog](https://cursor.com/blog/router) — **High** |
| Cost-effectiveness / comparable quality | Picks the most cost-effective model that still produces comparable quality | [docs](https://cursor.com/docs/cursor-router) — **High** |
| Optimization mode | Cost / Balance / Intelligence move the decision along a cost–intelligence tradeoff | [docs](https://cursor.com/docs/cursor-router), [help](https://cursor.com/help/models-and-usage/cursor-router.md) — **High** |
| Model pool membership | Routes across a stated pool; pool changes over time | [available models](https://cursor.com/help/models-and-usage/available-models.md) — **High** |
| Team model allow/block lists | Blocked models are skipped; blocking required models can disable Router | [docs](https://cursor.com/docs/cursor-router), [available models](https://cursor.com/help/models-and-usage/available-models.md) — **High** |
| Training / evaluation signal | Trained on 600k+ live requests; online A/B tests; optimizes user satisfaction (AFC); also tracks keep rate | [blog](https://cursor.com/blog/router) — **High** for Cursor’s own claims, not independently audited |
| Cache awareness | Router training/evaluation accounts for cache-miss costs from switching models mid-conversation | [blog](https://cursor.com/blog/router) — **High** |

Blog examples of intended specialization (illustrative, not a public rule table): “Simple work goes to the most price-efficient models, UI updates go to the model with the best taste, and more complex, long-horizon problems go to frontier reasoning models” ([blog](https://cursor.com/blog/router) — **High** as Cursor’s description; **Low** as a reproducible mapping of prompt → model).

### Explicit for Cost / previous Auto

| Factor | What Cursor says | Credibility |
| --- | --- | --- |
| “Previous Auto routing logic” | Cost mode uses previous Auto routing and keeps bundled Auto pricing | [docs](https://cursor.com/docs/cursor-router), [help](https://cursor.com/help/models-and-usage/cursor-router.md) — **High** |
| Token spend optimization | Cost optimizes token spend | [docs](https://cursor.com/docs/cursor-router) — **High** |
| Capacity / demand / availability / load | Repeated staff + older blog claims | [June 2025 blog](https://cursor.com/blog/june-2025-pricing), [deanrie](https://forum.cursor.com/t/auto-model-mechanism-in-cursor/159697), [kevinn](https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163) — **Medium-High** |
| Regional availability | Auto chooses an available model when regional restrictions apply | [regions](https://cursor.com/docs/account/regions) — **High** |

### Stated model pool for Cursor Router

Cursor Help currently lists Router routing across ([available models](https://cursor.com/help/models-and-usage/available-models.md) — **High**):

- Composer 2.5 (fast and standard)
- GPT-5.5
- Claude Opus 5
- Grok 4.5 (**required**; blocking it disables the router)
- Claude Fable 5

Recommended: GPT-5.5 and Claude Opus 5; blocking one reduces quality, blocking both disables the router.

This is a **published Router pool**, not a guarantee that every Auto Cost / individual Auto request uses only these models, and not a guarantee that every listed model is equally likely.

### Related but not the full Auto story: Composer behind Auto

Cursor has said it ships improved Composer checkpoints “behind Auto” via real-time RL as often as every five hours, using production interaction signals ([real-time RL blog](https://cursor.com/blog/real-time-rl-for-composer) — **High**). That shows Auto can also be a deployment surface for Cursor’s own models, not only a third-party model picker.

Staff have also confirmed Composer 2.5 is one model Auto may choose, and the usage dashboard can show the resolved model after the fact ([forum](https://forum.cursor.com/t/acp-composer-2-5-model-is-always-used-when-auto-is-selected/162832/5) — **Medium-High**).

---

## 3. Factors people often assume — evidence check

| Hypothesis | Evidence | Assessment |
| --- | --- | --- |
| Task complexity / type | Explicit in Router docs/blog and older staff replies | **Supported** |
| Query / context / domain | Explicit in Router blog | **Supported for Router** |
| Cost / optimization mode | Explicit Cost/Balance/Intelligence controls | **Supported** |
| Provider capacity / load / downtime | Staff + older blog; not detailed in Router classifier docs | **Supported as a constraint**, especially for legacy/Cost and fallback behavior |
| Regional availability | Official regions docs + staff | **Supported** |
| Team allow/block lists | Official Router docs | **Supported on Teams/Enterprise** |
| User satisfaction / keep-rate online metrics | Router blog training/eval story | **Supported as training objective**, not as a per-request visible score |
| Context-window size as an explicit selector | No first-party statement found that Auto chooses by remaining context length | **Unverified** |
| Exact public quality benchmarks (e.g. “Auto = Sonnet X”) | Staff: Auto does not map to one benchmarked model | **Rejected** ([forum](https://forum.cursor.com/t/auto-model-mechanism-in-cursor/159697) — **Medium-High**) |
| Privacy Mode changes routing | No first-party claim found that Privacy Mode alters Auto’s model-choice policy | **Unverified** |
| Geography beyond provider regional restrictions | Regions docs cover provider restrictions; no broader geo-routing whitepaper found | **Only regional provider availability is evidenced** |
| User tier / remaining quota soft-steers model choice | Billing docs describe pools and rates; no doc says Auto downgrades intelligence when quota is low. Separate claim: requests are “never downgraded in quality or speed” after included usage if on-demand continues ([models & pricing](https://cursor.com/docs/models-and-pricing) — **High** for on-demand continuity). Soft quota-based routing remains **Unverified**. |
| Tool-support matrix | No public Auto rule like “if MCP needed → model Y” found | **Unverified** |

---

## 4. When the choice happens, and whether it sticks

Evidence is slightly inconsistent across staff replies and product eras:

- Colin (2026-07): picks **before each turn**, keeps that model for the whole answer, may change on later turns ([forum](https://forum.cursor.com/t/how-often-does-auto-mode-switch-model/164805) — **Medium-High**).
- deanrie (2026-05): model can change **from step to step**; later reply says within one request, and often even within one step, different models may be used under the hood ([forum](https://forum.cursor.com/t/auto-model-mechanism-in-cursor/159697) — **Medium-High**, but the “within one step” claim is stronger and less operationally precise).
- danperks (2025): client may not know the model until the response finishes ([forum](https://forum.cursor.com/t/auto-mode-please-inform-us-which-is-the-exact-model-being-used/96733?page=2) — **Medium-High**, older).
- Router blog: routing is evaluated across conversations and model switches, including cache-miss costs ([blog](https://cursor.com/blog/router) — **High**).

**Working synthesis (Inference, Medium):** Auto is **request/turn-scoped**, not conversation-pinned. Sticky behavior may be preferred for caching, but is not guaranteed. Claims of mid-step multi-model use should be treated cautiously unless Cursor publishes a clearer definition of “step.”

---

## 5. Visibility into the Auto-routed model

Distinguish two identities:

| Identity | Meaning | Typical value under Auto |
| --- | --- | --- |
| **Selected** | What the user / API / hook configured in the model picker | `Auto`, `default`, `auto-smart`, plus an optimize-for mode |
| **Resolved** | The concrete backend that answered the turn | e.g. `composer-2.5`, a Claude/GPT/Grok slug |

Cursor’s product posture is that Auto should be judged on results, not model brand: routed identity is **hidden by default** ([docs](https://cursor.com/docs/cursor-router), [help](https://cursor.com/help/models-and-usage/available-models.md) — **High**). There is no first-party, real-time, documented external stream that emits “Auto just resolved to X” for every turn. Asking the model to name itself is unreliable under Auto ([related research](cursor-agents-cli-automation.md) — **Inference**).

### 5.1 First-party / staff-confirmed surfaces

| Surface | Selected vs resolved | Timing | Notes | Credibility |
| --- | --- | --- | --- | --- |
| Default chat UI | Selected only (`Auto`) | Live | Routed model hidden by design | [docs](https://cursor.com/docs/cursor-router), [help](https://cursor.com/help/models-and-usage/available-models.md) — **High** |
| Team admin **Underlying model: Displayed** | Resolved shown in product | Live / per turn | Applies to Balance and Intelligence; hidden is default and recommended | [docs](https://cursor.com/docs/cursor-router) — **High** |
| Usage dashboard | Resolved can appear after the fact | After the fact | Staff: Auto isn’t a model; dashboard intentionally shows the model that ran (e.g. `composer-2.5` after an Auto turn). Older staff also pointed users at the dashboard for post-hoc visibility | [kevinn](https://forum.cursor.com/t/acp-composer-2-5-model-is-always-used-when-auto-is-selected/162832/5), [deanrie](https://forum.cursor.com/t/is-there-a-way-to-know-what-model-is-selected-for-a-given-prompt-in-auto-mode/156470) — **Medium-High** |
| Billing / pools for Balance & Intelligence | Indirect resolved signal | After the fact | Charges at the routed model’s rate / pool; Cost mode does **not** reveal identity via price (bundled Auto rates) | [models & pricing](https://cursor.com/docs/models-and-pricing), [forum](https://forum.cursor.com/t/introducing-cursor-router/166386) — **High** / **Medium-High** |
| SDK | Selected router id | At call config | Model id `auto-smart` with `optimize_for`; confirms Router availability, not per-turn resolution | [docs](https://cursor.com/docs/cursor-router) — **High** |
| Cloud Agents API | Selected routing mode | At request | Staff: use `model: "default"` for Auto-style routing; `"auto"` as a key is confusing | [forum](https://forum.cursor.com/t/cursor-cloud-agents-api-auto-model-not-working/152289) — **Medium-High** |
| Enterprise Analytics API (plans metric) | Selected Auto collapsed to `default` | Aggregates | Docs: Auto selection is returned as model name `default`, not the resolved backend | [analytics API](https://cursor.com/docs/account/teams/analytics-api) — **High** for that endpoint’s behavior |

Staff have also said there historically was **no** way to see the exact model when using Auto in the UI ([Colin](https://forum.cursor.com/t/which-auto-model-was-used/150988) — **Medium-High**, pre-Router Displayed setting). Community feature requests still argue that transcripts and some dashboard views lack per-step Auto routing detail ([forum](https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163) — **Low–Medium** as product claim).

### 5.2 Hooks, CLI, and Skills (selected ≠ resolved)

| Mechanism | What it exposes | Useful for Auto resolution? | Credibility |
| --- | --- | --- | --- |
| Hooks common input (`model`, optional `model_id`, `model_params`) | Configured / selected model metadata at lifecycle events | **No** for resolved Auto — under Auto you typically log the router label. `beforeSubmitPrompt` fires **before** the backend finishes routing | [hooks docs via related research](cursor-agents-cli-automation.md), [hook granularity forum](https://forum.cursor.com/t/loss-of-model-granularity-in-beforesubmitprompt-hook-following-the-latest-agent-update/159386) — **High** / **Medium-High** |
| CLI `stream-json` system init `model` | Selected model for the run | **No** for per-turn Auto resolution; Auto may still route individual requests differently | [CLI output format via related research](cursor-agents-cli-automation.md) — **High** |
| Skills / prompt self-ID | Whatever the model claims | **No** — not authoritative under Auto | [related research](cursor-agents-cli-automation.md) — **Inference** |

Community note on the same feature thread: hooks can log selected `model` / `model_params` / `composer_mode` at submit time, while transcript JSONL often omits per-message model metadata ([forum community](https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163) — **Low** for the transcript claim; hooks field list aligns with docs — **Medium-High**).

### 5.3 Local client state (unofficial)

Community reports that the desktop app already stores the resolved model even when the UI hides it:

- `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (macOS), table `cursorDiskKV`, keys like `bubbleId:…`, JSON path `modelInfo.modelName` ([forum community](https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163) — **Low**; plausible, unaudited, schema can change).
- `~/.cursor/ai-tracking/ai-code-tracking.db` / `ai_code_hashes` allegedly attributes generated code blocks to a model ([same thread](https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163); [DEV reverse-engineering write-up](https://dev.to/vikram_ray/i-reverse-engineered-cursors-ai-agent-heres-everything-it-does-behind-the-scenes-3d0a) — **Low**).

**Assessment:** best *unofficial* on-machine path for resolved Auto identity; not a supported API; treat as fragile.

### 5.4 Intercepting / proxying Cursor ↔ backend traffic

**Feasibility of TLS interception:** Cursor staff state the client does **not** implement SSL pinning and that HTTPS inspection with a trusted proxy CA is feasible; LLM traffic goes to Cursor API domains (`api2.cursor.sh` and related), not directly to model providers ([forum](https://forum.cursor.com/t/does-cursor-client-implement-ssl-pinning-that-prevents-https-traffic-inspection/160355) — **Medium-High**). Common practical blockers are HTTP/2 proxy compatibility, untusted proxy CA on the Node path (`NODE_EXTRA_CA_CERTS`), and `http.proxySupport` not set to force the proxy.

**Does that reveal the Auto-resolved model?**

| Observation | Implication | Credibility |
| --- | --- | --- |
| Routing is server-side | Outbound chat/agent requests typically carry the **selected** router id (`auto` / `default` / `auto-smart`), not the concrete backend | Product design in [Router docs](https://cursor.com/docs/cursor-router) — **High**; RE clients pass Auto through as an identifier — **Low** |
| Agent payloads are Connect-RPC / protobuf over HTTP/2 | Bodies are not casual JSON; durable monitors need a decoder that tracks Cursor’s schema | Community RE ([nhan665 research](https://github.com/nhan665/cursor-opencode-auth/blob/main/RESEARCH.md), [eisbaw/cursor_api_demo](https://github.com/eisbaw/cursor_api_demo)) — **Low** |
| Resolved identity may appear only late | Older staff: the answered model may not be known until the response finishes | [danperks](https://forum.cursor.com/t/auto-mode-please-inform-us-which-is-the-exact-model-being-used/96733?page=2) — **Medium-High**, older era |
| No first-party guarantee of a scrapeable per-frame `modelName` | MITM is useful for DLP / prompt inspection; **weak and fragile** as a primary Auto-resolution monitor | Synthesis — **Inference (Medium)** |

**Assessment:** yes, you can often decrypt Cursor↔backend traffic; no, MITM is not a reliable primary way to learn which model Auto picked. Prefer usage dashboard (official) or local client DB (unofficial) over protocol scraping.

### 5.5 Practical ranking

| Goal | Prefer | Avoid relying on |
| --- | --- | --- |
| See resolved model in the IDE (Teams/Enterprise Router) | Admin **Displayed** underlying model | Default hidden Auto UI |
| Audit after the fact | Usage dashboard; Balance/Intelligence billing lines | Asking the model its name |
| Real-time external / SIEM-style Auto resolution | No supported first-party stream found | Hooks at submit; CLI init `model`; Analytics `default` bucket alone |
| On-machine forensic / tooling | Unofficial `state.vscdb` read (accept breakage) | MITM protobuf scraping as the only source |
| Deterministic, reproducible model identity | Pin a named model | Auto |

---

## 6. Plan and pricing interactions that affect interpretation

These do not fully explain *which* model is chosen, but they change what “Auto” means economically and which router you get:

- Start plan (India): does **not** include Auto ([models & pricing](https://cursor.com/docs/models-and-pricing) — **High**).
- Teams/Enterprise: Cursor Router picks Auto model by optimization mode ([models & pricing](https://cursor.com/docs/models-and-pricing) — **High**).
- Auto Cost: fixed bundled per-million-token rates regardless of underlying model ([models & pricing](https://cursor.com/docs/models-and-pricing), [help](https://cursor.com/help/models-and-usage/available-models.md) — **High**).
- Auto Balance / Intelligence: billed at the routed model’s API rate; third-party routes can incur Cursor Token Rate on Teams/Enterprise ([models & pricing](https://cursor.com/docs/models-and-pricing) — **High**).
- Staff: Auto Cost draws from first-party quota; Balance/Intelligence bill against the pool of the selected underlying model ([forum](https://forum.cursor.com/t/introducing-cursor-router/166386) — **Medium-High**).
- Help: Balance is default for new users; Cost is legacy Auto equivalent ([help](https://cursor.com/help/models-and-usage/cursor-router.md) — **High**).

Community surprise after the Router launch: some users report Auto migrating to Balance and billing frontier rates unexpectedly ([forum discussion](https://forum.cursor.com/t/introducing-cursor-router/166386) — **Low–Medium** as anecdote, but useful as a warning that Auto’s billing semantics changed).

---

## 7. Bottom line

**Known with decent confidence**

1. Auto is server-side routing over a changing model pool, not a single model identity.
2. On Teams/Enterprise after 2026-07-22, Auto is primarily **Cursor Router**: an ML classifier using query/context/task-complexity/domain signals, steered by Cost/Balance/Intelligence, constrained by the published pool and team allow/block rules.
3. Availability, load, downtime, and regional provider restrictions are longstanding Auto constraints, still relevant as fallback / Cost / non-Router behavior.
4. Exact algorithm, weights, thresholds, and live mix ratios are intentionally unpublished.
5. Individual-plan Auto is **not** the same product surface as Teams Router Auto today.
6. **Resolved-model visibility** is limited by design: Displayed admin toggle and usage/billing are the main first-party paths; hooks/CLI expose selection; MITM is interceptable but a poor Auto-resolution signal (§5).

**Unknown / not publicly evidenced**

1. The classifier feature set beyond Cursor’s high-level description (token counts? file types? tool intent? conversation length?).
2. Whether Cost mode uses the same classifier with a different objective, or a separate legacy policy.
3. Hard rules for mid-turn / mid-step model changes.
4. Whether remaining quota or spend limits alter model choice before hard refusal.
5. A complete, versioned public allowlist for individual Auto / Auto Cost.
6. Whether every Auto response path includes a stable, documented wire-format field for the resolved model (vs only client-local persistence / usage events).

**Practical takeaway:** if you need a reproducible model, pick a named model. Auto optimizes Cursor’s quality/cost/availability objectives, not caller-visible determinism. If you only need post-hoc visibility, use the usage dashboard (and Router Displayed on Teams); do not expect hooks or a simple MITM JSON field to name the routed backend.

---

## Sources by trust band

### High (first-party docs / blog / changelog)

- https://cursor.com/docs/cursor-router
- https://cursor.com/help/models-and-usage/cursor-router.md
- https://cursor.com/help/models-and-usage/available-models.md
- https://cursor.com/docs/models-and-pricing
- https://cursor.com/docs/account/regions
- https://cursor.com/blog/router
- https://cursor.com/changelog/router
- https://cursor.com/blog/june-2025-pricing
- https://cursor.com/blog/aug-2025-pricing
- https://cursor.com/blog/real-time-rl-for-composer
- https://cursor.com/docs/account/teams/analytics-api

### Medium-High (Cursor staff on forum)

- https://forum.cursor.com/t/auto-model-mechanism-in-cursor/159697
- https://forum.cursor.com/t/how-often-does-auto-mode-switch-model/164805
- https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163
- https://forum.cursor.com/t/introducing-cursor-router/166386
- https://forum.cursor.com/t/acp-composer-2-5-model-is-always-used-when-auto-is-selected/162832/5
- https://forum.cursor.com/t/auto-mode-please-inform-us-which-is-the-exact-model-being-used/96733?page=2
- https://forum.cursor.com/t/which-models-used-in-auto-mode/149187
- https://forum.cursor.com/t/is-there-a-way-to-know-what-model-is-selected-for-a-given-prompt-in-auto-mode/156470
- https://forum.cursor.com/t/cursor-cloud-agents-api-auto-model-not-working/152289
- https://forum.cursor.com/t/which-auto-model-was-used/150988
- https://forum.cursor.com/t/does-cursor-client-implement-ssl-pinning-that-prevents-https-traffic-inspection/160355
- https://forum.cursor.com/t/loss-of-model-granularity-in-beforesubmitprompt-hook-following-the-latest-agent-update/159386

### Low (community / reverse engineering)

- https://forum.cursor.com/t/show-which-model-handled-each-step-when-using-auto-mode/164163 (community SQLite / transcript claims)
- https://github.com/eisbaw/cursor_api_demo
- https://github.com/nhan665/cursor-opencode-auth/blob/main/RESEARCH.md
- https://dev.to/vikram_ray/i-reverse-engineered-cursors-ai-agent-heres-everything-it-does-behind-the-scenes-3d0a
- Related in-repo note: [cursor-agents-cli-automation.md](cursor-agents-cli-automation.md) (hooks / CLI selected-model fields)
