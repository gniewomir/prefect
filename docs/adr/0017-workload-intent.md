# Workload Intent (not Desired State / Host status)

The Workload Manifest declares **Workload Intent** — the post–Workload Setup expectation of what must be true after Setup succeeds — never observed Host status or a report of what is currently on the server. Values are **run**, **stop**, and **trash**; the Manifest field is `intent`. The three-mode behaviour and **Purge** semantics stay as in ADR-0014; this ADR renames the ubiquitous language so the Manifest cannot be mistaken for live status. Domain prose uses Intent wording only (no “running/stopped/trashed Workload”).

**Workload Intent + `run`|`stop`|`trash` over Workload Desired State + `running`|`stopped`|`trashed`:** Desired State and participial values read as “what is true on the server now”; Intent and verb-form values keep a declarative post-Setup expectation without sounding like Host status.

**Manifest key `intent` only (reject `state`, no dual-read):** wire format matches the glossary; no standing out-of-repo Manifests required a transition window.

**Strict Intent prose over mixed past-participle shorthand:** one vocabulary in glossary, ADRs, and tests.
