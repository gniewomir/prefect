# Workload shape and interaction policy

Prefect needed a single architectural stance for how a Workload is shaped and how Workloads interact on a Host — without turning soft operator conventions into mandatory Setup enforcement, and without inventing multi-tenant isolation. This ADR records that policy: ownership boundary, three interaction surfaces, soft defaults plus a thin Host-shape hard floor, named Escape Hatches, and an optional later tighten path (no named loosen path). Wayfinder map [Workload shape and interaction policy](https://github.com/gniewomir/prefect/issues/86) is the decision audit trail; day-to-day truth is this ADR plus `CONTEXT.md`.

**Ownership boundary.** A Workload owns its definition-tree unit set (`quadlets/` + `systemd/`, split by consumer) and one Host Volume tree under `…/workloads/<basename>/`. The soft default runtime shape is one pod on the Service Network; operators may deviate. Components keep the same unit-tree shape without a Manifest (platform-owned lifecycle).

**Three surfaces — soft defaults.** (1) Service Network: join it; peers and Edge reach the Workload by **basename** via explicit pod `NetworkAlias=` (not Quadlet’s default `systemd-$name` pod name as the public identity). Intra-pod traffic uses localhost. (2) Host Volume: mount that owned tree (or a subtree) — soft scaffold mounts the whole tree RW at `/var/lib/workload`. (3) Host ports: Workloads publish none by default.

**Hard floor.** Only the Edge publishes Host ports 80/443. There is **no Escape Hatch** for colliding with that Host shape.

**Escape Hatches (soft surfaces only).** Not joining the Service Network; mounting any Host Volume path outside the owned tree; publishing any non-80/443 Host port. Possible but unsupported — not taught, scaffolded, or Acceptance-tested; ownership/Setup/Purge stay on the default contract.

**Unit kinds under Intent.** Always-on / On-demand / Ensure classified by authored file kind; Intent stays Workload-wide. Soft unit basenames: default pod `<workload>.pod`; every other unit `<workload>-<role>.…`; related families share a role stem.

**Delivery of soft conventions.** Deployable `environments/example/` (four named teaching Workloads) plus required Acceptance Tests over that Environment — not injection by Workload Setup. Soft policy is Prefect-side; Podman/Quadlet do not enforce join/publish conventions.

**Optional tighten later (no loosen path).** Soft enforcement remains the default stance. Future optional validation may hard-fail real cross-Workload conflicts, warn on convention divergence / Escape Hatches, and elevate warnings to errors only behind an operator-opt-in flag. There is no named policy loosen path; changing the hard floor later is ordinary ADR work.

**Same-operator security.** No multi-tenant isolation between hostile Workloads.

**Rejected:** hard enforcement of soft conventions by default; a named loosen hatch; Escape Hatch around Edge 80/443; treating Escape Hatches as supported alternate patterns; multi-tenant ACLs on this policy surface.
