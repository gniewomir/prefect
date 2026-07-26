# Prefect

Prefect is a self-hosted platform with a thin Workload contract for a solo operator. It provides a path between repeating infrastructure work for every small project, paying for managed infrastructure before it is justified, and accepting PaaS abstractions that become costly to leave.

Domain language: [`CONTEXT.md`](CONTEXT.md). Decisions: [`docs/adr/`](docs/adr/).

These principles guide Prefect's development. Prefect is pre-stability, and the current implementation does not yet satisfy all of them.

## Principles

### Own the foundation; preserve the exit

Prefer infrastructure and Host-shape dependencies we understand and control over opaque app-platform lock-in. Keep the Prefect-specific surface thin and Workload configuration portable, so changing provider or graduating a Workload requires adaptation rather than reinvention.

### Make infrastructure reproducible

The repository and its explicit inputs should be sufficient to recreate equivalent infrastructure from scratch, without undocumented manual steps or knowledge held only by the operator.

### Automate repetition; preserve meaningful decisions

Automate work that would otherwise be repeated across projects. Keep choices that materially shape infrastructure or Workload behavior explicit, inspectable, and under operator control.

### Declare intent; expose the mechanism

Prefect contracts describe desired outcomes, and applying the same declaration repeatedly should produce the same managed outcome. Except for a minimal Manifest, Workload configuration remains in the underlying software's native formats rather than being replaced by Prefect-specific abstractions. Prefect coordinates tools without concealing their operation behind hidden assumptions or implicit behavior.

### Prefer secure simplicity over generality

Choose opinionated, secure operator defaults and the smallest operational model suitable for a solo operator. Scale vertically while sensible; graduate exceptional Workloads rather than growing Prefect into an orchestrator.

### Make promises executable

Prefect states its contracts in documentation and verifies their observable behavior with tests. Provider implementations may differ internally, but must satisfy the same Acceptance and Lifecycle behavior.

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

**Durables** are the Reserved IP and the Host Volume. They survive **Park** and are reattached on the next **Apply**. They keep billing while Parked. **Teardown** removes them.

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

Further reading: [ADR-0016](docs/adr/0016-park-durables-teardown.md) (Park / Durables / Teardown), [`test/README.md`](test/README.md), [`lifecycle-test/README.md`](lifecycle-test/README.md).
