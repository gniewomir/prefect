# Cursor input / prompt-cache policy (vs chat persistence)

**Researched:** 2026-07-28  
**Question:** After restarting Cursor IDE (e.g. after an update), do currently active conversations remain cached? What is the current caching policy for input tokens in Cursor? What is the TTL for input/prompt cache, and what triggers the countdown (last request? conversation creation? idle time?)? Is there additional cost when resurrecting an old agent conversation whose input tokens may already have been evicted from Cursor’s (or the underlying provider’s) cache?  
**Scope:** Cursor Agent / chat conversations and prompt/input token caching; behavior across IDE restart / update; cache TTL and what starts/resets the countdown; cost implications of continuing an old conversation vs starting a new one after cache eviction; distinction between (a) conversation history persisted so the chat UI still opens and (b) provider-side prompt cache that discounts input tokens.  
**Method:** Prefer Cursor docs / Help / Learn, first-party pricing tables, named Cursor staff on the official forum, and provider docs only where Cursor explicitly documents pass-through of Anthropic/OpenAI/etc. prompt caching. Community anecdotes are labeled separately.

### Credibility labels used here

| Label | Meaning |
| --- | --- |
| **High** | Cursor docs, Help Center, Learn, pricing tables, or first-party blog; current first-party |
| **Medium-High** | Named Cursor staff on the official forum |
| **Medium** | Older first-party wording that may be superseded, or staff statements that leave mechanics underspecified; provider docs cited only because Cursor staff say Cursor passes through that provider’s cache |
| **Low** | Unverified user reports / community replies (not staff) |

---

## Verdict

1. **Do not conflate “chat still opens” with “prompt cache still warm.”** Conversation history is a local (workspace-scoped) persistence concern: past Agent chats are expected to remain findable after quit/reopen when the same workspace is opened ([Colin on history](https://forum.cursor.com/t/chat-history-not-persisting-despite-settings-enabled/148459) — **Medium-High**; [Colin on workspace ID / quit-reopen expectation](https://forum.cursor.com/t/chat-history-missing-but-local-state-and-transcripts-present/156422) — **Medium-High**). Prompt/input **token discount** caching is a separate, **provider-side** mechanism. Cursor builds prompts in a cache-friendly way and hands them to Anthropic/OpenAI/etc.; **the provider’s cache** decides hit vs full re-seed ([Colin](https://forum.cursor.com/t/understanding-write-cache/156915) — **Medium-High**).
2. **IDE restart / update alone is not documented as the thing that evicts the prompt cache.** Cursor staff say TTL and refresh behavior are defined by the model provider, are the same for local / Cloud Agent / self-hosted, and that Cursor **does not** do anything special to keep the cache warm ([Colin](https://forum.cursor.com/t/understanding-write-cache/156915), [Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686) — **Medium-High**). Restart only causes a miss if the gap since the last cache-using request exceeds that provider TTL (idle time), or if the next request’s **token prefix** no longer matches.
3. **TTL is provider-specific, not a single Cursor-wide number.** Staff summaries: **Anthropic ≈ 5 minutes** (sliding window: every cache hit extends it); **most OpenAI models up to ~24 hours**, with **GPT-5.6-family ≈ 30 minutes** ([Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686), [Colin](https://forum.cursor.com/t/does-fork-chat-affect-cache-and-how-long-does-cache-last/158272), [Colin](https://forum.cursor.com/t/understanding-write-cache/156915) — **Medium-High**). Anthropic’s own docs match the 5-minute default refreshed on use ([Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) — **Medium** as provider truth Cursor says it uses). OpenAI’s docs describe in-memory retention (~5–10 minutes idle, up to ~1 hour), extended retention up to 24h, and GPT-5.6+ eligibility of at least 30 minutes ([OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching) — **Medium**).
4. **What starts/resets the countdown: idle time since last successful use of that cached prefix (i.e. last request that hit it), not conversation creation time.** Anthropic: lifetime refreshed each time cached content is used; expires after inactivity ([Anthropic](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) — **Medium**; [Colin sliding window](https://forum.cursor.com/t/understanding-write-cache/156915) — **Medium-High**). Cursor staff: if a Claude conversation sits idle more than ~5 minutes, the next turn is a full re-seed / new cache write ([Colin](https://forum.cursor.com/t/understanding-write-cache/156915) — **Medium-High**).
5. **Yes — resurrecting a long-idle conversation typically incurs extra cost vs continuing while the cache was warm.** After eviction, the next turn must re-process / re-seed the large shared prefix (Anthropic: billed as **cache write**, ~1.25× input; then later turns again get cheap **cache reads** if still warm) ([Condor](https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538) — **Medium-High**; [models & pricing](https://cursor.com/docs/models-and-pricing) — **High**). Merely opening an old chat in the UI does not itself bill tokens; **sending the next Agent turn** does, and that turn still includes the full chat context (caching changes **billing class**, not whether context is sent) ([Condor](https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538) — **Medium-High**).
6. **Current Cursor policy (billing + mechanics):** Prompt caching is automatic; there is no user toggle to disable cache read/write ([Condor](https://forum.cursor.com/t/how-to-disable-cache-write-and-cache-read/118864); [Mohit on Anthropic markers](https://forum.cursor.com/t/anthropic-prompt-caching/160861) — **Medium-High**). Usage surfaces `cacheWriteTokens` / `cacheReadTokens` ([SDK](https://cursor.com/docs/sdk/typescript), [Cloud Agent API](https://cursor.com/docs/cloud-agent/api/endpoints) — **High**). Per-model API rates include Cache write / Cache read columns ([models & pricing](https://cursor.com/docs/models-and-pricing) — **High**). Some first-party Cursor models (Grok / Composer) may not show separate cache-write charges even when reads appear ([Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686) — **Medium-High**).

**Practical summary:** After an IDE restart or update, expect the **conversation to still be in history** (same workspace path). Do **not** expect the **provider prompt cache** to still be warm unless you send another request within that model’s TTL. For Claude in Cursor, that window is typically **~5 minutes of idle** since the last cache hit. Continuing a large, cold conversation pays a **re-seed** (often a cache write) on the first post-idle turn; that is usually more expensive than the cheap cache-read path of an actively warm thread, and can be more expensive than starting a **smaller new** chat if you no longer need the old context.

---

## 1. Two layers: chat persistence vs prompt cache

| Layer | What it is | Survives IDE restart? | Affects token $$? |
| --- | --- | --- | --- |
| **(a) Conversation / Agent history** | Messages, tool traces, UI thread identity stored for the workspace so you can reopen the chat | **Intended yes** (same folder / workspace ID); failures are usually orphaned workspace IDs, not “cache TTL” | **No** by itself — opening history is not an API call |
| **(b) Provider prompt / input cache** | Provider reuses a prior **exact prompt prefix** and bills those tokens as cache read (cheaper) instead of full input / cache write | **Only if** idle &lt; provider TTL **and** prefix still matches | **Yes** — changes input billing class per request |

### (a) Conversation persistence

- History is **workspace-specific**; open the same project folder to see past chats ([Colin](https://forum.cursor.com/t/chat-history-not-persisting-despite-settings-enabled/148459) — **Medium-High**).
- On Linux, workspace ID also salts on folder **inode**; rename/move/inode change orphans UI history while data may still exist on disk ([Colin](https://forum.cursor.com/t/chat-history-missing-but-local-state-and-transcripts-present/156422) — **Medium-High**).
- Staff debugging assumes quit → reopen **should** keep chats for a fixed test folder ([Colin test plan](https://forum.cursor.com/t/chat-history-missing-but-local-state-and-transcripts-present/156422) — **Medium-High**).
- After some upgrades, IDE sidebar history can look empty while Agents Window still lists chats from disk ([staff on upgrade history](https://forum.cursor.com/t/ide-chat-history-empty-after-upgrade-to-3-11-13-agents-window-still-shows-project-chats/165382) — **Medium-High**). That is an indexing/UI binding issue, not prompt-cache TTL.

Cursor also documents that each chat has a **context window**; when full, older turns are **summarized** into the prompt ([prompting docs](https://cursor.com/docs/agent/prompting) — **High**). That is context management inside the conversation payload, separate from provider prompt caching.

### (b) Prompt / input token cache

- Each Agent step (message, tool call, follow-up) is its own API call; Cursor must send the **full chat context** every time — caching does not mean “send only the diff” ([Condor](https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538) — **Medium-High**).
- Billing classes (staff):
  - First establishment of a cached prefix → **cache write** (often slightly above normal input; Anthropic separates this).
  - Later exact-prefix reuse within TTL → **cache read** (much cheaper).
  - New tokens each step (latest user message, new tool results) → normal **input**.
  - Model output → normal **output** always.
  ([Condor](https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538) — **Medium-High**)
- Cursor Learn: tools “automatically cach[e] parts of your prompt that you use repeatedly” as a cost optimization ([tokens & pricing](https://cursor.com/learn/tokens-pricing) — **High**, high-level only).

---

## 2. Current Cursor caching policy (what first-party sources state)

### Documented in Cursor docs / product surfaces

| Claim | Source | Credibility |
| --- | --- | --- |
| Model pricing tables list **Input**, **Cache write**, **Cache read**, **Output** (per 1M tokens) | [Models & Pricing](https://cursor.com/docs/models-and-pricing) | **High** |
| Anthropic-style writes often ~1.25× input; reads ~0.1× input (e.g. Claude 4.6 Opus $5 / $6.25 / $0.5) | same | **High** |
| Many OpenAI/Google rows show cache **read** without a separate write column (write folded into input or provider-specific) | same | **High** |
| Token usage APIs/SDK expose `cacheWriteTokens` / `cacheReadTokens` | [TypeScript SDK](https://cursor.com/docs/sdk/typescript), [Cloud Agent endpoints](https://cursor.com/docs/cloud-agent/api/endpoints) | **High** |
| Cache read tokens = “Tokens served from the prompt cache”; cache write = “Tokens written to the prompt cache” | [TypeScript SDK](https://cursor.com/docs/sdk/typescript) | **High** |

### Staff / policy (mechanics Cursor does not put on the pricing page)

| Claim | Source | Credibility |
| --- | --- | --- |
| Cursor builds prompts cache-friendly; **provider** owns hit/miss and duration | [Colin](https://forum.cursor.com/t/understanding-write-cache/156915) | **Medium-High** |
| Same cache behavior local vs Cloud Agent vs self-hosted | same | **Medium-High** |
| Cursor uses **standard provider caching**; **no special keep-alive** | [Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686) | **Medium-High** |
| Anthropic caching automatic; cache_control markers placed server-side; **no user setting** | [Mohit](https://forum.cursor.com/t/anthropic-prompt-caching/160861) | **Medium-High** |
| Cannot disable cache read/write | [Condor](https://forum.cursor.com/t/how-to-disable-cache-write-and-cache-read/118864) | **Medium-High** |
| Cache reads ~10% of input price; without them input cost ~9× higher for reused context | [Condor](https://forum.cursor.com/t/how-to-disable-cache-write-and-cache-read/118864) | **Medium-High** |
| Forked chats can still cache-hit if cache not expired | [Colin](https://forum.cursor.com/t/does-fork-chat-affect-cache-and-how-long-does-cache-last/158272) | **Medium-High** |
| Cache hits can occur **across chats** for stable prefixes (e.g. system prompt) | [Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686) | **Medium-High** |
| Prefix must match exactly; model switch / edit earlier message / toggle tools-rules → re-seed even inside TTL | [Colin](https://forum.cursor.com/t/understanding-write-cache/156915) | **Medium-High** |
| GPT-5.4 extended cache up to 24h; Privacy Mode → shorter default; MAX mode does not change caching | [Mohit](https://forum.cursor.com/t/gpt-5-4-cache-tokens/157332) | **Medium-High** |
| Cursor Grok (like Composer) doesn’t charge for cache writes (so usage may show reads without writes) | [Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686) | **Medium-High** |

---

## 3. TTL and what triggers the countdown

### Cursor staff TTL summary (authoritative for “what Cursor uses”)

| Provider / family | TTL as stated by Cursor staff | Countdown / refresh |
| --- | --- | --- |
| **Anthropic (Claude)** | ~**5 minutes**; sliding window | Every **cache hit** extends; idle &gt; ~5 min → full re-seed + new cache write ([Colin](https://forum.cursor.com/t/understanding-write-cache/156915), [Colin](https://forum.cursor.com/t/does-fork-chat-affect-cache-and-how-long-does-cache-last/158272), [Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686)) |
| **Most OpenAI models** | Up to **24 hours** | Provider-defined; Cursor does not keep warm ([Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686)) |
| **GPT-5.6 family** | **30 minutes** (Colin corrected after OpenAI docs) | Same pass-through rule ([Colin](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686)) |
| **GPT-5.4** (staff detail) | Extended up to **24 hours** if Privacy Mode allows; shorter if Privacy Mode on | Prefix-based; subagents get **separate** cache entries ([Mohit](https://forum.cursor.com/t/gpt-5-4-cache-tokens/157332)) |

### Provider docs Cursor’s policy points at (pass-through)

**Anthropic** ([prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) — **Medium**):

- Default lifetime **5 minutes**; refreshed at no extra cost each time cached content is used.
- Optional **1-hour** TTL at higher write price; Cursor staff say Cursor uses the **default ~5m** window, not that users can opt into 1h inside Cursor ([Colin](https://forum.cursor.com/t/understanding-write-cache/156915) — **Medium-High**; community requests for 1h pass-through — **Low**).
- Manual clear not available; expires after inactivity.

**OpenAI** ([prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching) — **Medium**):

- **In-memory:** typically **5–10 minutes** of inactivity, up to about one hour.
- **Extended:** up to **24 hours**.
- **GPT-5.6+:** cached prefixes eligible for reuse for **at least 30 minutes** (may be retained longer); API `ttl` default discussed as `30m` in reference docs.
- Matches Colin’s “24h for most OpenAI / 30m for GPT-5.6+” staff summary.

### Explicit non-triggers (from primary sources)

| Event | Evicts prompt cache? |
| --- | --- |
| Conversation **created** at time T | **No** — TTL is not “age of thread” |
| **IDE restart / update** by itself | **Not documented** as eviction; only the resulting **idle gap** and next **prefix** matter |
| **Last request** that **hits** the cache | **Resets / extends** sliding TTL (Anthropic; staff) |
| Idle longer than provider TTL | **Yes** — next turn re-seeds |
| Model switch / edit history / tool-rule toggle changing prefix | **Yes** — miss even inside TTL ([Colin](https://forum.cursor.com/t/understanding-write-cache/156915)) |

---

## 4. Cost of continuing an old / cold conversation

### What you pay after eviction

Condor’s worked example (Opus-class rates): without caching, reused 1M context × 20 steps is far more expensive than 1× cache write + 19× cache reads ([forum](https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538) — **Medium-High**). The inverse after a miss: the **first** post-idle turn looks like a **warm-start again** (cache write or full input), then subsequent turns in the next TTL window get cheap reads again.

So for a **large** Agent thread left idle past Anthropic’s ~5 minutes (including most update/restart downtime):

1. UI reopen: **no** token charge from history alone.
2. First new message: **re-seed cost** on the large prefix (cache write on Anthropic).
3. Further messages within TTL: cheap cache reads again **if** prefix stays stable.

That is **additional cost relative to never going cold**, not relative to “tokens vanished forever.” Relative to **starting a new chat**:

- **Continue cold large thread:** pay to re-cache (or re-input) the accumulated context.
- **New small thread:** pay only for the new, smaller prompt — often cheaper if old context is no longer needed.
- **Continue warm thread:** cheapest for multi-step Agent work (many tool calls reusing the same prefix) ([Condor](https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538), [Condor](https://forum.cursor.com/t/how-to-disable-cache-write-and-cache-read/118864) — **Medium-High**).

### Restart after update — typical cost picture

| Situation | History UI | Prompt cache | First follow-up cost |
| --- | --- | --- | --- |
| Restart &lt; ~5 min idle, same Claude model, unchanged prefix | Present | Likely still warm | Mostly cache **reads** + new input |
| Restart / coffee break &gt; ~5 min idle on Claude | Present | Likely cold | Cache **write** (or full input) for large prefix |
| Long idle on OpenAI with 24h extended cache (Privacy Mode allowing) | Present | May still be warm | More likely cache **reads** |
| Long idle on GPT-5.6 (~30 min TTL per staff) | Present | Cold if idle &gt; ~30 min | Re-seed / miss |

No primary Cursor source states “restarting the IDE flushes the provider cache immediately.”

---

## 5. Community / Low-credibility notes (labeled)

- Users report taking breaks &gt;5 minutes yet “feeling” cached; Colin attributes snappiness partly to **cross-chat** hits on stable system prefixes, not a longer Cursor-owned TTL ([thread](https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686) — user **Low**; staff reply **Medium-High**).
- Users arguing Cursor should expose Anthropic **1h** TTL (`ENABLE_PROMPT_CACHING_1H`) — product request, not current policy ([thread](https://forum.cursor.com/t/understanding-write-cache/156915) — **Low**).
- Claude Code–side analyses of Anthropic 5m vs 1h TTL regressions are **not** Cursor docs ([linked discussion](https://forum.cursor.com/t/understanding-write-cache/156915) — **Low** for Cursor behavior).

---

## 6. Open gaps (not answered by primary sources)

1. **Exact** mapping of Cursor Privacy Mode → OpenAI `prompt_cache_retention` / ZDR for every model (staff state Privacy Mode shortens GPT-5.4 extended cache; full matrix unpublished).
2. Whether Cursor ever requests Anthropic **1h** TTL for any product surface, or only the default **5m**.
3. Whether **in-flight** Agent runs interrupted by IDE kill preserve provider cache differently than idle completed turns.
4. Precise cost comparison algorithm for “continue cold long thread vs new chat” (depends on summarized vs full history, model, Privacy Mode) — only qualitative staff guidance exists.
5. No Cursor Help article titled “prompt cache TTL”; policy is assembled from pricing tables + staff forum answers + provider docs.

---

## Sources (primary)

| Source | URL | Role |
| --- | --- | --- |
| Models & Pricing (Docs) | https://cursor.com/docs/models-and-pricing | Cache write/read API rates per model |
| Tokens & Pricing (Learn) | https://cursor.com/learn/tokens-pricing | High-level automatic prompt caching |
| Agent prompting (Docs) | https://cursor.com/docs/agent/prompting | Context window / summarization (≠ provider cache) |
| TypeScript SDK TokenUsage | https://cursor.com/docs/sdk/typescript | `cacheReadTokens` / `cacheWriteTokens` definitions |
| Cloud Agent API endpoints | https://cursor.com/docs/cloud-agent/api/endpoints | Usage fields including cache tokens |
| Staff: Colin — provider owns cache; Anthropic ~5m sliding | https://forum.cursor.com/t/understanding-write-cache/156915 | TTL, re-seed on idle, prefix match gotchas |
| Staff: Colin — no keep-alive; OpenAI 24h / GPT-5.6 30m | https://forum.cursor.com/t/how-long-does-cursors-prompt-cache-persist-before-expiring/165686 | Pass-through policy; Grok no cache-write charge |
| Staff: Colin — fork + Anthropic 5m TTL | https://forum.cursor.com/t/does-fork-chat-affect-cache-and-how-long-does-cache-last/158272 | Fork hits if not expired |
| Staff: Condor — why cache read/write are billed | https://forum.cursor.com/t/someone-please-explain-why-are-cache-read-and-write-chargeable/153538 | Full context each call; write vs read economics |
| Staff: Condor — cannot disable cache | https://forum.cursor.com/t/how-to-disable-cache-write-and-cache-read/118864 | Automatic provider caching; ~10% read pricing |
| Staff: Mohit — Anthropic caching automatic | https://forum.cursor.com/t/anthropic-prompt-caching/160861 | Server-side cache_control; no user toggle |
| Staff: Mohit — GPT-5.4 cache / Privacy Mode | https://forum.cursor.com/t/gpt-5-4-cache-tokens/157332 | Up to 24h; Privacy Mode shortens; subagent separate cache |
| Staff: Colin — chat history workspace-scoped | https://forum.cursor.com/t/chat-history-not-persisting-despite-settings-enabled/148459 | Persistence ≠ prompt cache |
| Staff: Colin — workspace ID / quit-reopen tests | https://forum.cursor.com/t/chat-history-missing-but-local-state-and-transcripts-present/156422 | Expected history survival across restart |
| Staff: upgrade sidebar vs Agents Window | https://forum.cursor.com/t/ide-chat-history-empty-after-upgrade-to-3-11-13-agents-window-still-shows-project-chats/165382 | History can look missing after upgrade while on disk |
| Anthropic prompt caching | https://platform.claude.com/docs/en/build-with-claude/prompt-caching | 5m default TTL refreshed on use; optional 1h |
| OpenAI prompt caching | https://developers.openai.com/api/docs/guides/prompt-caching | In-memory vs 24h extended; GPT-5.6+ ≥30m |
| OpenAI Prompt Caching announcement | https://openai.com/index/api-prompt-caching/ | Historical 5–10 min inactivity wording |
