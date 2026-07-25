# Prefect

Infrastructure-as-code for Hosts and related cloud resources. Domain language: [`CONTEXT.md`](CONTEXT.md). Decisions: [`docs/adr/`](docs/adr/).

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
