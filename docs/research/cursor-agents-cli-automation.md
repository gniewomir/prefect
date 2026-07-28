# Cursor Agent Skills, CLI automation, context, and billing

**Researched:** 2026-07-28  
**Question:** How do Cursor Agent Skills, model selection, CLI/headless operation, context controls, authentication, and billing fit together for local and remote automation?  
**Scope:** Cursor IDE, Cursor CLI, Cloud Agents, and the Cursor SDK as currently documented. Primary sources only: Cursor documentation, Help Center, Terms of Service, and Master Services Agreement.  
**Method:** Claims marked **Inference** combine multiple official pages where Cursor does not make the full statement in one place. An absence claim means no field or behavior is present in the current documented interface; it is not a promise about undocumented internals.  
**Related:** [Cursor Agent sandbox and host isolation](cursor-agent-sandbox-security.md)

---

## Verdict

1. A Skill can **recommend** a model in its instructions, but Skills have no documented model-selection field or operation that changes the parent conversation's model. The user can change the parent model; a custom subagent can independently use `inherit` or a specific model ID ([Skills](https://cursor.com/docs/skills), [changing models](https://cursor.com/docs/agent/prompting#changing-models), [subagent model configuration](https://cursor.com/docs/subagents#model-configuration)).
2. A Skill has no documented runtime API for reliably discovering the parent model. Asking the model to identify itself is not a sound substitute, especially under Auto, where Cursor may route requests to different models. Hooks can receive selected-model metadata, but hooks are a separate executable policy mechanism, not Skill runtime state ([Skills frontmatter](https://cursor.com/docs/skills#skillmd-file-format), [Cursor Router](https://cursor.com/docs/cursor-router), [hook input](https://cursor.com/docs/hooks#common-input)).
3. Cursor CLI supports interactive and fully non-interactive/headless Agent runs, including a selected model, direct file changes, and shell execution. It is explicitly documented for scripts and CI/CD ([CLI overview](https://cursor.com/docs/cli/overview), [headless mode](https://cursor.com/docs/cli/headless), [GitHub Actions](https://cursor.com/docs/cli/github-actions)).
4. Cursor explicitly describes CLI as the same Agent with the same usage tracking as the IDE. Both therefore use the authenticated identity's account-level pools and model rates; Cursor documents no separate CLI quota ([CLI deployment considerations](https://cursor.com/docs/enterprise/deployment-patterns#cursor-cli-considerations), [SDK pricing](https://cursor.com/docs/sdk/typescript#pricing-and-privacy), [models and pricing](https://cursor.com/docs/models-and-pricing)).
5. A normal paid-plan user API key can authenticate automated CLI and eligible SDK/Cloud Agent workflows. This is a Cursor credential, distinct from optional BYOK provider credentials. Included usage is finite, and unattended automation can consume it quickly ([CLI authentication](https://cursor.com/docs/cli/reference/authentication), [API overview](https://cursor.com/docs/api), [models and pricing](https://cursor.com/docs/models-and-pricing), [BYOK](https://cursor.com/help/models-and-usage/api-keys)).

---

## 1. Agent Skills and model selection

### What a Skill can do

A Skill is instructions plus optional scripts and references. At startup Cursor discovers Skill descriptions; Agent decides when a Skill is relevant, then progressively loads its `SKILL.md` and supporting material as needed. A Skill can therefore say, for example, “for this task, prefer a fast model” or “delegate this to a subagent using model X.” That recommendation is ordinary instruction text, not an enforced model switch ([Skills](https://cursor.com/docs/skills)).

The documented Skill frontmatter is:

- `name`
- `description`
- optional `paths`
- optional `disable-model-invocation`
- optional arbitrary `metadata`

There is no documented Skill `model` field. Arbitrary `metadata` is descriptive data, not documented as controlling the active model ([Skill format](https://cursor.com/docs/skills#skillmd-file-format)).

### Parent model versus subagent model

The parent conversation's model is selected by the user through the IDE model picker or, in CLI, `--model` and `/model`. Cursor says an IDE model change applies to the current conversation going forward ([IDE model changing](https://cursor.com/docs/agent/prompting#changing-models), [CLI parameters](https://cursor.com/docs/cli/reference/parameters), [CLI configuration](https://cursor.com/docs/cli/reference/configuration#model-configuration)).

A custom subagent has a separate documented `model` field:

- `inherit` uses the parent model and is the default.
- A specific model ID requests that exact model for the subagent.

Plan access, team model restrictions, and legacy-plan/Max Mode rules can override that configuration. On some legacy request-based plans without Max Mode, Cursor documents that subagents run with Composer regardless of the configured model ([subagent model configuration](https://cursor.com/docs/subagents#model-configuration)).

The accurate control boundary is narrower than “the parent controls the subagent model”:

- With `model: inherit`, the custom subagent follows the model selected for the parent.
- With a specific model ID, the subagent definition—not the parent invocation—selects the requested model.
- The parent can choose which available custom subagent to invoke, but Cursor documents no per-invocation model override argument. Natural-language instructions such as “run this subagent with model X” are not a documented override mechanism.
- Built-in Explore, Bash, and Browser subagents choose models automatically; their definitions and model selection are not exposed for user editing.
- Auto is a router rather than a concrete model. Cursor does not document whether an inheriting subagent re-routes independently or receives the parent turn's routed backend, so neither behavior should be assumed ([subagents](https://cursor.com/docs/subagents), [Cursor Router](https://cursor.com/docs/cursor-router)).

### User-defined subagents

Users can create and modify custom subagent definitions as Markdown files containing YAML frontmatter followed by the subagent's instructions:

- Project scope: `.cursor/agents/`, `.claude/agents/`, or `.codex/agents/`
- User scope: `~/.cursor/agents/`, `~/.claude/agents/`, or `~/.codex/agents/`

The documented fields are `name`, `description`, `model`, `readonly`, and `is_background`. `description` guides automatic delegation; `readonly` prevents edits and state-changing commands; `is_background` controls whether the subagent normally runs asynchronously. Cursor does not document `tools` as a definition field: subagents inherit parent tools, including MCP tools, subject to applicable policies.

Definitions can be created manually, by asking Agent to create one, or through the Customize page. A custom subagent can be invoked automatically from its description, explicitly with `/name`, or through a natural-language request. Project definitions override same-named user definitions, and `.cursor/` takes precedence over compatible `.claude/` and `.codex/` locations within a scope. Cursor does not document whether definition edits hot-reload or require restarting a session ([subagents](https://cursor.com/docs/subagents), [Customize Cursor](https://cursor.com/docs/customize-cursor)).

**Inference:** A Skill may recommend invoking a configured, model-pinned custom subagent. The effective model still comes from that subagent's definition and availability rules; invoking it does not switch the already-running parent session.

---

## 2. Can a Skill detect the active parent model?

No documented Skill runtime field or API exposes the active parent model. The Skill schema contains static frontmatter and files; it does not define variables such as `current_model`, an environment API, or a callback that returns the parent selection ([Skills](https://cursor.com/docs/skills)).

Model self-identification is unreliable:

- A model may report a family or name from prompt context rather than authoritative runtime metadata.
- With Auto, Cursor Router can select a model for each request, so there may not be one stable underlying model for the whole conversation ([Cursor Router](https://cursor.com/docs/cursor-router)).
- A user-visible selected label and the actual model used for an individual routed request are not necessarily the same concept.

Hooks are the documented exception, but they are a **different mechanism**. Common hook input can include:

- `model`: legacy configured model slug
- optional `model_id`: structured selected model ID
- optional `model_params`: selected parameters such as thinking, context, or effort

Hooks execute commands or configured prompt checks at lifecycle/tool events. They do not make those fields available as a documented Skill variable, and app-lifecycle hooks outside an Agent session omit model fields ([Hooks common input](https://cursor.com/docs/hooks#common-input)).

Headless CLI can also report its selected model externally: `stream-json` emits a system initialization event with a `model` field. This can help an orchestration script record the run configuration, but it still does not expose the parent model to a running Skill, and an Auto selection may route individual requests differently ([CLI output format](https://cursor.com/docs/cli/reference/output-format#system-initialization)).

---

## 3. Starting Cursor CLI with a chosen model

### Interactive

```bash
# Start an interactive Agent session using a chosen model
agent --model "gpt-5"

# Start with an initial prompt
agent --model "gpt-5" "Inspect this repository"
```

The general documented option is `--model <model>`. Model availability is account- and policy-dependent, so list rather than guess IDs:

```bash
agent models
# Equivalent option form:
agent --list-models
```

Within an interactive session:

```text
/model
/model gpt-5
```

`/model [filter]` opens/selects from the model picker; Cursor's configuration guide also documents concrete `/model auto`, `/model gpt-5`, and `/model sonnet-4-thinking` examples ([CLI parameters](https://cursor.com/docs/cli/reference/parameters), [slash commands](https://cursor.com/docs/cli/reference/slash-commands), [CLI configuration](https://cursor.com/docs/cli/reference/configuration#model-configuration)).

### Headless/non-interactive

```bash
# Read-only/proposal-style run unless the task itself needs no writes
agent -p --model "gpt-5" "Analyze this project"

# Permit direct file changes without confirmation
agent -p --force --model "gpt-5" "Fix the failing tests"

```

`-p`/`--print` is non-interactive mode. It has access to write and shell tools; without `--force`, changes are proposed rather than applied. `--force` (alias `--yolo`) force-allows commands unless explicitly denied. Useful headless options include `--output-format text|json|stream-json`, `--stream-partial-output`, `--trust`, and `--approve-mcps` ([headless mode](https://cursor.com/docs/cli/headless), [CLI parameters](https://cursor.com/docs/cli/reference/parameters)). Sandboxing and approval boundaries are covered separately in [Cursor Agent sandbox and host isolation](cursor-agent-sandbox-security.md).

### Model caveats

- Fresh CLI installs currently default to Auto; an existing explicit choice is preserved ([CLI changelog](https://cursor.com/docs/cli/changelog)).
- Auto is routing, not a promise of one fixed underlying model for every request ([Cursor Router](https://cursor.com/docs/cursor-router)).
- Parent `--model` selection does not force every custom subagent to that model. Subagents can inherit, pin another model, or be overridden by plan/team rules ([subagents](https://cursor.com/docs/subagents#model-configuration)).
- Always use `agent models` for the authenticated account instead of relying on example IDs.

---

## 4. IDE versus CLI billing

Cursor's plan documentation defines account/seat usage pools and model rates, not separate IDE and CLI entitlements:

- Individual Pro, Pro Plus, and Ultra have a **Cursor Models** pool and an **Other Models** pool, reset on the monthly billing cycle.
- Other Models usage is valued at the model's API price; higher plans include larger allowances.
- Teams usage is allocated per paid user/seat unless an Enterprise contract uses pooled usage.
- Cloud Agents are charged at API pricing for the selected model.
- SDK runs explicitly follow the same pricing and request pools as IDE and Cloud Agents; a user key bills the user's plan, while a service-account key bills its owning team ([models and pricing](https://cursor.com/docs/models-and-pricing), [Teams pricing](https://cursor.com/docs/account/teams/pricing), [Cloud Agents](https://cursor.com/docs/cloud-agent#pricing), [SDK pricing and identity](https://cursor.com/docs/sdk/typescript#pricing-and-privacy)).

**Shared IDE/CLI usage:** Cursor's Enterprise deployment guidance explicitly describes CLI as “the same agent with a different interface” and says it has the same usage tracking as the IDE. Combined with account-scoped authentication and pricing, IDE and CLI activity for one identity draws on that identity's account pools; no separate CLI allowance is documented ([CLI deployment considerations](https://cursor.com/docs/enterprise/deployment-patterns#cursor-cli-considerations), [CLI authentication](https://cursor.com/docs/cli/reference/authentication)).

### Included usage and on-demand usage

Included usage is consumed before billable overage. Once included usage is exhausted, behavior depends on plan and settings:

- Individual-plan docs offer enabling on-demand usage or upgrading.
- Teams docs say on-demand is **enabled by default**, can be controlled with spending limits, and is used after included pools are exhausted.
- Start has no Other Models pool and does not include on-demand usage, Auto, or the SDK.

Therefore, the accurate rule is: **pay-as-you-go overage is charged only while on-demand usage is enabled for the account/team, but Teams may already have it enabled by default.** It is too strong to say every user must personally and explicitly enable it first ([models and pricing](https://cursor.com/docs/models-and-pricing#what-happens-when-i-reach-my-limit), [Teams on-demand pricing](https://cursor.com/docs/account/teams/pricing#on-demand-usage)).

### Cloud handoff

From CLI, prefixing a message with `&` hands the task to a Cloud Agent that continues away from the local terminal and can be resumed on web or mobile. That changes the execution environment and invokes Cloud Agent pricing; it does not create a separate subscription pool ([CLI Cloud Agent handoff](https://cursor.com/docs/cli/using#cloud-agent-handoff), [Cloud Agent pricing](https://cursor.com/docs/cloud-agent#pricing)).

---

## 5. Context control

Three concepts must remain separate:

1. **Available/searchable:** Agent can discover a file, indexed chunk, rule description, Skill description, or MCP tool.
2. **Actually inserted:** The prompt contains selected file contents, rule/Skill text, tool schemas, conversation text, or tool results.
3. **Fixed product context:** Cursor's built-in system instructions and tool definitions occupy context independently of repository files.

Indexing or MCP discovery does not mean all indexed code or all external data is copied into every model request. Agent searches and reads relevant material; those results then enter conversation context ([search tools](https://cursor.com/docs/agent/tools/search), [prompt context breakdown](https://cursor.com/docs/agent/prompting#context-window)).

### IDE

- `@` can attach files/folders, docs, terminal output, past chats, git diffs, and browser context. If the relevant files are unknown, Agent can search for them itself ([prompting](https://cursor.com/docs/agent/prompting#mentions)).
- Cursor indexes codebases for search. `.cursorignore` blocks normal Agent/Tab/Inline Edit and `@` access; `.cursorindexingignore` only removes files from indexing while leaving direct AI access possible. `.gitignore` and Cursor defaults also affect indexing ([ignore files](https://cursor.com/docs/reference/ignore-file)).
- `.cursor/rules/*.mdc` can be always applied, glob-triggered, Agent-selected by description, or manually `@`-mentioned. Root and nested `AGENTS.md` files provide plain-Markdown instructions for matching directory scopes ([Rules and AGENTS.md](https://cursor.com/docs/rules)).
- Skill descriptions are surfaced initially; full Skill instructions and referenced files load progressively when relevant. `paths` limits surfacing, and `disable-model-invocation: true` requires explicit `/skill-name` invocation ([Skills](https://cursor.com/docs/skills)).
- Connected MCP servers contribute instructions/tool catalogs; actual calls return external data into the conversation ([MCP](https://cursor.com/docs/mcp)).
- The context ring shows usage split into system prompt, tools, rules, Skills, MCP, subagents, summarized conversation, and conversation/tool results. Cursor automatically compresses older history near the limit ([context window](https://cursor.com/docs/agent/prompting#context-window)).
- Start a fresh chat to discard prior conversational context; model changes apply only going forward in the existing conversation.

### CLI

- CLI supports `@` selection for files and folders.
- It uses the same `.cursor/rules` system and reads root `AGENTS.md` and `CLAUDE.md`.
- It discovers the same `mcp.json` configuration as the editor.
- `/context` visualizes context consumption by category.
- `/summarize` (alias `/compress`) reduces conversation history; `/clear` starts a new session.
- `--resume [chatId]`, `--continue`, `agent resume`, and `agent ls` restore existing conversations rather than starting without history ([CLI using](https://cursor.com/docs/cli/using), [CLI slash commands](https://cursor.com/docs/cli/reference/slash-commands), [CLI MCP](https://cursor.com/docs/cli/mcp), [CLI changelog](https://cursor.com/docs/cli/changelog)).

### What cannot be configured away

Cursor documents its built-in system prompt and every available tool definition as context categories. It documents controls for repository instructions, attached content, Skills, MCP servers, and conversation compression, but no supported setting that removes the core system prompt or built-in tool schemas. **This is an absence-of-interface finding, not a guarantee about internal implementation** ([context window breakdown](https://cursor.com/docs/agent/prompting#context-window)).

Security implications of `.cursorignore`, shell access, MCP, approvals, and process isolation are covered in [Cursor Agent sandbox and host isolation](cursor-agent-sandbox-security.md).

---

## 6. Running CLI on a remote or cloud machine

Cursor explicitly supports CLI in scripts, CI pipelines, GitHub Actions, cron jobs, and other non-interactive environments. A normal remote host is therefore a supported deployment location provided it can run the CLI and reach Cursor's APIs ([headless CLI](https://cursor.com/docs/cli/headless), [GitHub Actions](https://cursor.com/docs/cli/github-actions), [service accounts](https://cursor.com/docs/account/enterprise/service-accounts#using-service-accounts-with-the-cli)).

### Browser login on a remote host

```bash
agent login
agent status
agent logout
```

For a host without a browser:

```bash
NO_OPEN_BROWSER=1 agent login
```

Cursor prints a URL to open elsewhere. After completion, credentials are securely stored locally. Cursor does not document a guaranteed credential lifetime. Its CLI changelog says expired tokens prompt re-login, so describe credentials as **locally persisted until logout, revocation, expiry, or another invalidating event**, not permanent ([CLI authentication](https://cursor.com/docs/cli/reference/authentication), [CLI changelog](https://cursor.com/docs/cli/changelog)).

### API-key authentication

```bash
export CURSOR_API_KEY="your_cursor_api_key"
agent -p --force --model "<model-id>" "Your task"
```

User API keys are created from Cursor Dashboard → API Keys and are documented for automation, scripts, and CI. Passing `--api-key` is supported, but an environment variable or secret store avoids exposing the key in process arguments and shell history ([CLI authentication](https://cursor.com/docs/cli/reference/authentication)).

### Personal key versus Enterprise service account

- A **user API key** represents and bills to that user/plan. It is suitable for the user's own automation.
- An **Enterprise service account** is a non-human identity, has API keys, consumes the team's usage pool like a human user, and does not consume a seat. Cursor recommends it for CI/CD, cron, and non-interactive workflows that should not depend on a person ([service accounts](https://cursor.com/docs/account/enterprise/service-accounts), [SDK identity and billing](https://cursor.com/docs/sdk/typescript#authentication)).
- Service accounts change identity, lifecycle, attribution, and administration; they do **not** create free model usage or different base model prices.

Do not share one person's login among multiple people. The MSA requires that an Authorized User's login not be shared by multiple people, and the consumer Terms require confidentiality of account credentials. Use separate users or an eligible service account instead ([MSA, Customer Responsibilities](https://cursor.com/terms/msa), [Terms of Service, Account Registration and Access](https://cursor.com/terms-of-service)).

---

## 7. Core conclusion for automated paid-plan use

**Inference from the authentication, pricing, and SDK documentation:** A normal paid Cursor subscription can back fully automated/headless CLI runs through a user `CURSOR_API_KEY`. The same user key is also accepted by the SDK's local and cloud runtimes, and the Cloud Agents API accepts user keys where the endpoint permits them. These are Agent-workflow interfaces, not a generic chat-completions/model-inference API ([CLI authentication](https://cursor.com/docs/cli/reference/authentication), [SDK authentication](https://cursor.com/docs/sdk/typescript#authentication), [API overview](https://cursor.com/docs/api)).

Billing consequences:

1. The user key bills to the user's plan; a service-account key bills to its team.
2. **Inference:** eligible runs consume included subscription pools first because Cursor applies model usage to the authenticated account and documents on-demand as what happens after included usage is exhausted.
3. Pay-as-you-go is used only while on-demand usage is enabled. On Teams, it is enabled by default unless changed, so it is not always the result of a user manually opting in.
4. Pools are finite. Long prompts, large contexts, repeated tool output, multiple agents, and long unattended loops can consume included usage quickly.
5. Plan restrictions remain: Start has no Other Models pool, on-demand usage, Auto, Automations, or SDK, although it includes Cursor Models and Cloud Agents.
6. Cloud Agents and SDK runs use normal model/request-pool pricing; service accounts alter identity and governance, not prices.

### Cursor API key is not BYOK

`CURSOR_API_KEY` authenticates to Cursor services and charges the corresponding Cursor user/team plan. BYOK means configuring a separate OpenAI, Anthropic, Google, Azure, or AWS Bedrock credential so eligible chat-model inference is paid to that provider. BYOK is optional, has separate privacy/billing implications, and does not replace Cursor authentication for CLI/SDK/Cloud Agent APIs ([CLI authentication](https://cursor.com/docs/cli/reference/authentication), [BYOK](https://cursor.com/help/models-and-usage/api-keys), [Teams BYOK pricing](https://cursor.com/docs/account/teams/pricing#cursor-token-rate)).

---

## 8. Alternatives and trade-offs

| Approach | State and filesystem | Survives caller disconnect? | Identity | Tooling boundary | Billing |
| --- | --- | --- | --- | --- | --- |
| Persistent remote CLI | Uses the remote host's working tree and locally persisted CLI conversation/auth state; durability is the operator's responsibility | The process survives only if the host/process manager, `tmux`, CI job, etc. keeps it alive; a stopped process can later resume saved chats | User browser login, user API key, or Enterprise service account key | Host file tools, shell, and local MCP configuration | Same usage tracking as IDE against the authenticated account; no separate CLI quota is documented |
| Cloud Agent / CLI `&` handoff | Cursor-hosted isolated VM, cloned repository, separate branch, configured environment/snapshots | Yes; designed to continue away from the local terminal and resume on web/mobile | Cursor user or eligible service account/API caller | Cloud VM; cloud/team MCP and secrets, not the local machine's MCP/home-directory state | API pricing for selected model; paid plan required |
| SDK local runtime | Works against local disk; local conversation/run metadata persists in a workspace-scoped state root | Can resume after process restart when that local state remains; the active run itself depends on the caller/runtime | User or service-account `CURSOR_API_KEY` | Local files and tools with configurable hooks and policies; inference remains hosted by Cursor | Same pricing/request pools as IDE and Cloud Agents; SDK-tagged usage |
| SDK cloud runtime | Cursor VM with repo cloned; conversation persists server-side | Yes; can resume from another machine | User or service-account `CURSOR_API_KEY` | Cloud environment, project/team config and cloud-appropriate MCP/secrets | Same pricing/request pools as IDE and Cloud Agents |
| Ephemeral CI runner using CLI or local SDK | Fresh checkout and runner filesystem; persist artifacts/caches explicitly | Continues only for the CI job's lifetime; retry is normally a new runner unless state is restored | Prefer secret-injected user key for personal automation or Enterprise service account for organizational automation | CI runner permissions, secrets, network policy, hooks, and Agent permissions | Authenticated user's/team's usage; CI compute is billed separately by the CI provider |

Sources for the comparison: [CLI using and resume](https://cursor.com/docs/cli/using), [CLI deployment considerations](https://cursor.com/docs/enterprise/deployment-patterns#cursor-cli-considerations), [Cloud Agents](https://cursor.com/docs/cloud-agent), [CLI GitHub Actions](https://cursor.com/docs/cli/github-actions), [TypeScript SDK runtimes and persistence](https://cursor.com/docs/sdk/typescript), [service accounts](https://cursor.com/docs/account/enterprise/service-accounts).

No option is universally best:

- Choose persistent remote CLI when the remote checkout itself is authoritative and the operator wants full control of machine lifecycle.
- Choose Cloud Agents when disconnection survival, isolation, parallel branches, and Cursor-managed environments matter more than exact local-machine state.
- Choose local SDK when building a programmatic workflow around an existing working tree.
- Choose cloud SDK/API when the caller should orchestrate durable remote runs without hosting the execution environment.
- Choose CI runners for event-driven, reproducible jobs whose state can be represented by the checkout, caches, and artifacts.

---

## Corrections and caveats

- “A Skill can select the model” is too broad. It can recommend one; custom subagent definitions, CLI flags, SDK/API inputs, and the user-facing picker are the documented selection mechanisms.
- “The parent controls the subagent model” is also too broad. A custom subagent inherits the parent model by default or requests the model configured in its definition; the parent has no documented per-invocation model override. Built-in subagents choose automatically.
- “A Skill can inspect the current model” is undocumented. Hooks may receive selected-model metadata, but that is not a Skill API, and Auto may route per request.
- “On-demand charges happen only after I explicitly opt in” is not universally true. Teams documentation says on-demand is enabled by default.
- “CLI login credentials are permanent” is unsupported. They persist locally, but Cursor does not specify expiry and documents re-login for expired tokens.
- “Service accounts make automation cheaper” is unsupported. They provide non-human identity and governance while consuming the team's usage pool.
- “BYOK is required for headless CLI” is false. A Cursor user or service-account API key authenticates Cursor automation; provider BYOK is optional and distinct.

---

## Sources

- [Cursor Agent prompting, model changing, and context window](https://cursor.com/docs/agent/prompting)
- [Ignore files](https://cursor.com/docs/reference/ignore-file)
- [Rules and `AGENTS.md`](https://cursor.com/docs/rules)
- [Agent Skills](https://cursor.com/docs/skills)
- [Custom subagents](https://cursor.com/docs/subagents)
- [Hooks](https://cursor.com/docs/hooks)
- [Cursor Router / Auto](https://cursor.com/docs/cursor-router)
- [CLI overview](https://cursor.com/docs/cli/overview)
- [Using Cursor CLI](https://cursor.com/docs/cli/using)
- [CLI headless mode](https://cursor.com/docs/cli/headless)
- [CLI parameters](https://cursor.com/docs/cli/reference/parameters)
- [CLI slash commands](https://cursor.com/docs/cli/reference/slash-commands)
- [CLI configuration](https://cursor.com/docs/cli/reference/configuration)
- [CLI authentication](https://cursor.com/docs/cli/reference/authentication)
- [CLI MCP](https://cursor.com/docs/cli/mcp)
- [CLI GitHub Actions](https://cursor.com/docs/cli/github-actions)
- [CLI changelog](https://cursor.com/docs/cli/changelog)
- [Enterprise deployment patterns](https://cursor.com/docs/enterprise/deployment-patterns)
- [Models and pricing](https://cursor.com/docs/models-and-pricing)
- [Teams pricing](https://cursor.com/docs/account/teams/pricing)
- [Cloud Agents](https://cursor.com/docs/cloud-agent)
- [Cursor API overview](https://cursor.com/docs/api)
- [Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints)
- [TypeScript SDK](https://cursor.com/docs/sdk/typescript)
- [Python SDK](https://cursor.com/docs/sdk/python)
- [Enterprise service accounts](https://cursor.com/docs/account/enterprise/service-accounts)
- [BYOK API keys](https://cursor.com/help/models-and-usage/api-keys)
- [Cursor Terms of Service](https://cursor.com/terms-of-service)
- [Cursor Master Services Agreement](https://cursor.com/terms/msa)
