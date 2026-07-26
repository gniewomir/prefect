# Prefect

Prefect is a self-hosted platform that lets a solo operator reuse infrastructure across small projects through a thin Workload contract—without paying for managed infrastructure too early or becoming dependent on a PaaS that is costly to leave.

Domain language: [`CONTEXT.md`](CONTEXT.md). Decisions: [`docs/adr/`](docs/adr/).

These principles guide Prefect's development. Prefect is pre-stability, and the current implementation does not yet satisfy all of them.

## Principles

### Own the foundation; preserve the exit

Prefer infrastructure we understand and control over opaque app-platform dependencies. Keep the Prefect-specific surface thin and Workload configuration portable, so changing provider or graduating a Workload requires adaptation rather than reinvention.

### Automate repetition; preserve meaningful decisions

Automate work that would otherwise be repeated across projects. Keep choices that materially shape infrastructure or Workload behavior explicit, inspectable, and under operator control.

### Declare intent; expose the mechanism

Prefect declarations describe desired outcomes, and applying one repeatedly should produce the same managed outcome. Except for a minimal Manifest, Workload configuration remains in the underlying software's native formats rather than being replaced by Prefect-specific abstractions. Prefect coordinates tools without concealing their operation behind hidden assumptions or implicit behavior.

### Prefer secure simplicity over generality

Choose opinionated, secure operator defaults and the smallest operational model suitable for a solo operator.

### Make infrastructure reproducible

The repository and its explicit inputs should be sufficient to recreate equivalent infrastructure from scratch, without undocumented manual steps or knowledge held only by the operator.

### Make promises executable

Prefect states its contracts in documentation and verifies their observable behavior with tests. Provider implementations may differ internally, but must satisfy the same Acceptance and Lifecycle behavior.

### Scale the Host; graduate the exceptions

Make Host capacity changes routine and low-disruption. Prefer vertical scaling while the shared Host remains sufficient; when a Workload outgrows that model, move it to dedicated infrastructure rather than expanding Prefect into a general-purpose orchestrator.

## Credentials

```bash
export DIGITALOCEAN_TOKEN=…
export TF_VAR_DIGITALOCEAN_PUBLIC_KEY="$(cat ~/.ssh/your_key.pub)"
```

Optional for SSH helpers: `SSH_IDENTITY=/path/to/private_key`.

## Environments

Every operator script takes an optional `--env <slug>`.

- Omit it (or pass `test` / `default`) → **test** Environment
- Any other slug (e.g. `prod`) → that Environment, only when you ask for it

Safe by default: nothing touches a non-test Environment unless you pass `--env` explicitly. Details: [ADR-0019](docs/adr/0019-environments.md).

## Durables

**Durables** are the Reserved IP, the Host Volume, and **Domain** (provider DNS zone plus Stack-authored A records → Reserved IP). They survive **Park** and are reattached on the next **Apply**. They continue to incur charges while Parked (Domain lifecycle ownership still applies when DNS itself is free). **Teardown** removes them.

Domains are optional (**0..N** per Environment). Configure via `TF_VAR_domains` (JSON) or a `.tfvars` file — map of apex FQDN → `{ names = ["@", "www", …] }`. Empty = no Domains. Registrar purchase and NS delegation to the provider stay **out of band**; the Stack owns the Domain only after the name is on the provider. Adopting an existing provider zone is one-shot import surgery — not Apply auto-adopt: [domain Durable import](docs/runbooks/domain-durable-import.md).

## Operations

| Script | What it does |
|--------|----------------|
| `./apply.sh [--yes] [--env <slug>]` | Bring the Stack up (or converge it). Interactive plan by default; `--yes` for automation. |
| `./park.sh [--env <slug>]` | Tear down the Host and other non-durables; keep Durables. For development and other non-production Environments — so you are not billed for a Host you are not using. Confirm by typing `park`. |
| `./teardown.sh [--env <slug>]` | Full wipe, including Durables. Stops Durable billing. Confirm by typing `teardown`. |
| `./diagnostics.sh [--env <slug>] --bundle <id> [--out <dir>]` | Pull a named Host diagnostics bundle for local inspection. `--bundle` is required (`ihp` today). |
| `./ssh.sh [--env <slug>] [ssh args…]` | SSH to the Host (root @ Reserved IP). |
| `./test.sh [--env <slug>] [selector]` | Acceptance Tests against an Applied Stack (non-destructive). |
| `./lifecycle-test.sh [--env <slug>] [selector]` | Lifecycle Tests (Park / Teardown; opt-in, destructive). |

Host-side helpers under `prefect/` (`ensure-components.sh`, `workload-setup.sh`, `purge-workloads.sh`) use the same `--env` rule.

Further reading: [ADR-0016](docs/adr/0016-park-durables-teardown.md) (Park / Durables / Teardown), [ADR-0020](docs/adr/0020-domain-durable.md) (Domain Durable), [`docs/runbooks/domain-durable-import.md`](docs/runbooks/domain-durable-import.md), [`test/README.md`](test/README.md), [`lifecycle-test/README.md`](lifecycle-test/README.md).
