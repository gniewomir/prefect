# Operator surface vs internals; Host-local function names

Day-to-day operator surface stays at the repo root; project wiring moves under brand-neutral `internals/`. Host-local identity is named by **function**, not project brand. Provider-visible labels stay deferred. Clean break (ADR-0018).

**Repository layout**

- **Root operator entrypoints** (high-level operations on the Environment / platform as a whole): `apply.sh`, `park.sh`, `teardown.sh`, `ssh.sh` only. Acceptance/Lifecycle runners, diagnostics, lint, ensure-components, Workload Setup, and Purge are not root entrypoints — they are internals (dev/debug/CI or cogs a future wider operation will compose). Scoped power (one Workload, one Component) belongs as options on platform-level entrypoints later, not as separate root scripts.
- **Root declarations and docs:** `environments/` (Environment intent — ADR-0033), `docs/`, and root `*.md` stay at root. Dotdirs stay at root.
- **`internals/`:** Stack (`terraform/`), operator helpers (`lib/`), Host Component ship surface (`components/`), test suites (`acceptance-tests/`, `lifecycle-tests/`), and a **flat** glanceable list of non-root operations (`acceptance-tests.sh`, `lifecycle-tests.sh`, `diagnostics.sh`, `lint-*.sh`, `ensure-components.sh`, `workload-setup.sh`, `purge-workloads.sh`, …). Components must live under `internals/components/` so the Host copy tar never shares a tree with Stack/docs/tests/operator `lib/`.
- **Rejected:** nesting internals under a project-brand directory (`prefect/`, later `propraetor/`); leaving today’s `prefect/` as both Component ship surface and junk drawer; root clutter of every runnable script; naming the Host mount or repo internals folder from the carrier metaphor.

**Host-local function names** (same cut as the layout move; not the Propraetor brand rename)

| Concern | Name |
|---------|------|
| Host Volume mount | `/var/lib/host-volume` |
| Platform User (Unix) | `platform` (`PLATFORM_USER`) |
| Environment slug env | `PLATFORM_ENV` |
| Host Volume systemd/IHP unit family | `host-volume.service` (and matching tmpfiles/udev) |
| SSH drop-in | `99-ssh-port.conf` |
| Edge nginx include dirs | `/etc/nginx/edge-domains`, `/etc/nginx/edge-routes` |
| Ephemeral staging | `/tmp/platform-*` |
| IHP contract gate | **Initial Host Provisioning Done** / **IHP Done** (replaces Carrier ready) |

**Deferred:** provider Cloud Project names, Prefect Tag / Role Tag strings, and other account-unique resource name prefixes — dedicated cutover with lifecycle Adopt/recreate matrix (ADR-0025). Project rename to Propraetor remains ADR-0027; Host paths/user are **not** brand-Propraetor.

**Builds on:** ADR-0010 (Host Volume layout — paths update), ADR-0018, ADR-0019 (Environment / `--env`), ADR-0027 (amended: Host-local ≠ brand).
