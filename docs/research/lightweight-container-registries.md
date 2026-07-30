# Lightweight container registries for Prefect Components

**Researched:** 2026-07-30  
**Question:** Is there a reputable project fitting “lightweight, containerized, container registry” that Prefect could use as (or inspire) a Component enabling push and fetch of container images via an already-existing solution?  
**Scope:** Self-hosted OCI / Docker Registry HTTP API V2 servers that can run as a container (rootless Podman / Quadlet-friendly) on a small Host. Managed registries (GHCR, Quay.io, GitLab.com registry) are out of scope except as non-fits. Clients and libraries (ORAS, go-containerregistry) are noted only to dismiss. Not a Prefect design doc.  
**Method:** Primary sources only — official project docs and READMEs, CNCF project pages, OCI Distribution Specification, first-party install/config guides, and GitHub release metadata. Secondary blogs used only as leads; claims verified against owning sources. Repo deployment context from [`CONTEXT.md`](../../CONTEXT.md) (Components as rootless Quadlets on a Host Volume) informs operational fit observations only.

---

## Verdict

**Yes.** Two reputable, actively maintained Go projects fit the brief well:

1. **[CNCF Distribution](https://github.com/distribution/distribution) (`registry:3`)** — the reference OCI Distribution Spec implementation; single container, filesystem storage, no database; start with `docker run … registry:3` ([docs home](https://distribution.github.io/distribution/), [deploy](https://distribution.github.io/distribution/about/deploying/)).
2. **[zot](https://github.com/project-zot/zot) (`ghcr.io/project-zot/zot-minimal`)** — OCI-native registry (OCI Distribution Spec on the wire, OCI Image Layout on disk); single binary / single container; explicit **minimal** image with Dist Spec only ([concepts](https://zotregistry.dev/v2.1.18/general/concepts/), [getting started](https://zotregistry.dev/v2.1.18/admin-guide/admin-getting-started/), [released images](https://zotregistry.dev/v2.1.18/general/releases/)).

Neither publishes measured idle RAM/CPU in primary docs; both are single-process servers with optional filesystem bind-mounts — the right *shape* for a low-footprint Host Component. Enterprise platforms (Harbor, Nexus, Quay, Artifactory) and P2P accelerators (Dragonfly, Kraken, Spegel) are **not** fits for this priority list.

**Strongest overall for this criteria order:** **Distribution `registry:3`** for absolute simplicity and “just store and serve,” with **`zot-minimal`** as the equally serious alternative when OCI Image Layout on disk and a first-party minimal/embedded build matter more than the Docker-era default image.

---

## Decision criteria

Ordered for this question:

1. **Low resource footprint** on a solo-operator / small Host (idle and light use). Prefer few processes, no mandatory SQL/Redis stack. Published vendor minima are not observed RSS ([same evidence policy as the DB research note](lightweight-relational-databases.md)).
2. **Minimal API** — OCI Distribution Spec / Registry HTTP API V2 push+pull; avoid large control planes.
3. **Simplicity** — few moving parts, official container image, small config surface, Quadlet-friendly (one long-lived container + Host Volume bind-mount).
4. **Reputable** — CNCF or established org, recent releases, clear ownership.
5. **Go** preferred when candidates are otherwise similar.

---

## Shortlist

| Tier | Candidate | Shape | Why it remains / exits |
| --- | --- | --- | --- |
| A | CNCF Distribution (`registry:3`) | Single Go registry container | Reference Dist Spec server; one container; filesystem storage; optional htpasswd |
| A | zot / **zot-minimal** | Single Go binary or container | OCI-native; CNCF Sandbox; minimal Dist Spec build; Podman examples first-party |
| Reject (heavy) | Harbor | Multi-container platform | Graduated CNCF, but min 4 GB RAM and many services |
| Reject (heavy) | Sonatype Nexus Repository | JVM multi-format repo | Small profile starts at 8 GB RAM |
| Reject (heavy) | Project Quay / Red Hat Quay | App + PostgreSQL + Redis (+ Clair) | Feature-rich; multi-component by design |
| Reject (wrong job) | Spegel | Cluster-local **pull mirror** | Not a push registry; Kubernetes/containerd-oriented |
| Reject (wrong job) | Dragonfly, Uber Kraken | P2P distribution / acceleration | Scale-out image *delivery*, not a minimal private registry |
| Reject (managed) | GHCR, Quay.io, GitLab.com registry | SaaS | Not a self-hosted Component |
| Reject (not a server) | ORAS, go-containerregistry | Client / library | No registry daemon |
| Skip | Joxit docker-registry-ui | UI only | Does not include a registry |

---

## Tier A — serious candidates

### 1. CNCF Distribution (`registry:3`)

**What it is.** The open-source registry implementation for storing and distributing container images and other content using the [OCI Distribution Specification](https://github.com/opencontainers/distribution-spec). Stated goal: “a simple, secure, and scalable base for building a large scale registry solution or running a simple private registry.” It is a core library/backend for operators including Docker Hub, GitHub Container Registry, GitLab Container Registry, DigitalOcean Container Registry, and Harbor ([README](https://github.com/distribution/distribution/blob/main/README.md)). Language: **Go** ([GitHub languages / repo metadata](https://github.com/distribution/distribution)). License: Apache-2.0.

**Maintenance / reputation.** Donated to CNCF; accepted as a CNCF **Sandbox** project on **January 26, 2021** ([CNCF Distribution](https://www.cncf.io/projects/distribution/)). Docker documents the transition: “Registry (now CNCF Distribution)” ([Docker deprecations — Registry](https://docs.docker.com/registry/)). Recent releases: **v3.1.1** (2026-05-01), **v3.1.0**, **v3.0.0** ([GitHub releases](https://github.com/distribution/distribution/releases)). Active `main` pushes through 2026-07.

**OCI / API.** Official docs: “The distribution registry implements the OCI Distribution Spec version **1.0.1**” ([docs home](https://distribution.github.io/distribution/)). Clients talk HTTP; push/pull as shown in the quickstart (`docker push` / `docker pull` against `localhost:5000`) ([docs home](https://distribution.github.io/distribution/), [deploy](https://distribution.github.io/distribution/about/deploying/)).

**How to run.** Primary path is the official **`registry:3`** image:

```text
docker run -d -p 5000:5000 --name registry registry:3
```

([docs home](https://distribution.github.io/distribution/), [deploy](https://distribution.github.io/distribution/about/deploying/)). Persist data with a bind mount to `/var/lib/registry` ([deploy — storage](https://distribution.github.io/distribution/about/deploying/)). Config is YAML (`/etc/distribution/config.yml`) or `REGISTRY_*` environment overrides ([configuration](https://distribution.github.io/distribution/about/configuration/)). The image builds a static `registry` binary from `./cmd/registry` ([Dockerfile](https://github.com/distribution/distribution/blob/main/Dockerfile)).

**Resource footprint (primary-source only).** No official idle RAM/CPU figures found. Architecture is a **stateless** HTTP server with pluggable storage; default storage is **local filesystem** under `/var/lib/registry` — no mandatory PostgreSQL/Redis ([docs home](https://distribution.github.io/distribution/), [config-dev.yml](https://github.com/distribution/distribution/blob/main/cmd/registry/config-dev.yml), [configuration](https://distribution.github.io/distribution/about/configuration/)). Optional Redis appears only as a cache when configured ([configuration](https://distribution.github.io/distribution/about/configuration/)). Default deploy docs warn that the stock config is for development (debug logging; OpenTelemetry may attempt `localhost:4318` unless `OTEL_TRACES_EXPORTER=none`) ([deploy](https://distribution.github.io/distribution/about/deploying/)).

**Auth at minimum viable config.** Default local `registry:3` examples run **without** authentication (explicitly “testing” / development) ([deploy](https://distribution.github.io/distribution/about/deploying/)). Production path: TLS + **native htpasswd** (bcrypt) via env vars, or delegated **token** auth (external token service) ([deploy — restricting access](https://distribution.github.io/distribution/about/deploying/), [configuration — auth](https://distribution.github.io/distribution/about/configuration/)). Htpasswd must be used with TLS; basic auth sends credentials in headers ([configuration — htpasswd](https://distribution.github.io/distribution/about/configuration/)).

**Feature surface.** Store and serve content via Dist Spec; storage drivers (filesystem, S3, GCS, Azure, …); optional notifications, proxy/pull-through, garbage collection tooling, Prometheus on debug addr in sample config ([configuration](https://distribution.github.io/distribution/about/configuration/), [config-dev.yml](https://github.com/distribution/distribution/blob/main/cmd/registry/config-dev.yml)). No built-in web UI, vulnerability scanner, or RBAC projects model — those are left to wrappers (e.g. Harbor).

**Operational fit (Quadlet / Host Volume).** One container + bind-mounted data directory matches a single Component Quadlet. Docs are Docker-oriented but the image is a normal OCI image; Podman can run the same image. No sibling DB container required for the filesystem driver.

**Deal-breakers for this use case.** None for “lightweight private registry.” Caveats: production wants TLS (and usually auth); GC and some ops are more manual than zot’s inline GC; storage layout is Distribution’s own layout, not OCI Image Layout on disk ([zot’s comparison notes this difference](https://github.com/project-zot/zot/blob/main/COMPARISON.md) — treat that file’s *release dates* as stale; verify releases elsewhere).

---

### 2. zot (full and minimal)

**What it is.** “A production-ready vendor-neutral OCI image registry — images stored in OCI image format, distribution specification on-the-wire, that's it!” ([README](https://github.com/project-zot/zot/blob/main/README.md)). Docs: production-ready, open-source, OCI-standards-only registry ([concepts](https://zotregistry.dev/v2.1.18/general/concepts/)). Architecture: “intends to be a production reference implementation for the OCI Distribution Specification”; does not support other vendor protocols; **only** OCI Image Layout on disk; **single binary** controlled by one config file ([architecture](https://zotregistry.dev/v2.1.18/general/architecture/)). Language: **Go** ([GitHub](https://github.com/project-zot/zot)). License: Apache 2.0 ([concepts](https://zotregistry.dev/v2.1.18/general/concepts/)).

**Maintenance / reputation.** CNCF **Sandbox** since December 13, 2022 ([CNCF zot](https://www.cncf.io/projects/zot/)). Recent releases through **v2.1.18** (2026-06-24) ([GitHub releases](https://github.com/project-zot/zot/releases)). Docs and GHCR images actively maintained ([released images](https://zotregistry.dev/v2.1.18/general/releases/)).

**OCI / API.** “zot fully conforms to the OCI Distribution Specification” ([concepts](https://zotregistry.dev/v2.1.18/general/concepts/)). Conformance badge/workflow on the repo ([README](https://github.com/project-zot/zot/blob/main/README.md)). Minimal example config sets `"distSpecVersion": "1.1.1"` ([config-minimal.json](https://github.com/project-zot/zot/blob/main/examples/config-minimal.json)).

**How to run.**

- **Container (Podman called out explicitly):**

  ```text
  podman run -p 5000:5000 ghcr.io/project-zot/zot:latest
  podman run -p 5000:5000 ghcr.io/project-zot/zot-minimal:latest
  ```

  ([getting started](https://zotregistry.dev/v2.1.18/admin-guide/admin-getting-started/)).

- **Images:** `ghcr.io/project-zot/zot` (full) and `ghcr.io/project-zot/zot-minimal` (Dist Spec only) ([released images](https://zotregistry.dev/v2.1.18/general/releases/)).
- **Binary + systemd:** download release binary, `zot serve /etc/zot/config.json`, dedicated non-root user ([Linux install](https://zotregistry.dev/v2.1.18/install-guides/install-guide-linux/)).
- Bind-mount storage example: `-v $(pwd)/registry:/var/lib/registry`; default auth disabled on sample container deploy ([getting started](https://zotregistry.dev/v2.1.18/admin-guide/admin-getting-started/)).

**Minimal vs full.** Architecture: `zot-full = zot-minimal + extensions`. Minimal = core Dist Spec; full adds extensions (search/UI/CVE/sync/…) ([architecture](https://zotregistry.dev/v2.1.18/general/architecture/)). Full image default config enables **search (with CVE scanning), ui, and mgmt** ([released images](https://zotregistry.dev/v2.1.18/general/releases/)). Minimal default config is storage + HTTP port + log only ([released images](https://zotregistry.dev/v2.1.18/general/releases/)). Concepts table: “Minimal build” = Dist Spec compliant registry with reduced libraries/attack surface; suitable to “embed a zot registry in a product” ([concepts](https://zotregistry.dev/v2.1.18/general/concepts/)).

**Resource footprint (primary-source only).** No official idle RSS numbers. Positioning: single binary; suitable for cloud, bare-metal, and **embedded devices**; Raspberry Pi called out as a supported arm64 platform ([concepts](https://zotregistry.dev/v2.1.18/general/concepts/), [getting started — platforms](https://zotregistry.dev/v2.1.18/admin-guide/admin-getting-started/)). Storage docs mention embedded devices with limited RAM and a `commit` option to flush writes sooner ([admin configuration](https://zotregistry.dev/v2.1.18/admin-guide/admin-configuration/)). Example systemd unit in the Linux guide sets `MemoryHigh=30G` / `MemoryMax=32G` — that is an **upper cgroup cap for a production-ish host example**, not a minimum requirement ([Linux install](https://zotregistry.dev/v2.1.18/install-guides/install-guide-linux/)). **Full** image with CVE search downloads Trivy DBs and needs write access + `/tmp` space ([Linux install — CVE notes](https://zotregistry.dev/v2.1.18/install-guides/install-guide-linux/)) — avoid that path if footprint is the priority; use **zot-minimal** or disable extensions.

**Auth at minimum viable config.** Minimal config can omit auth entirely ([config-minimal.json](https://github.com/project-zot/zot/blob/main/examples/config-minimal.json), [getting started](https://zotregistry.dev/v2.1.18/admin-guide/admin-getting-started/)). Built-in options: mTLS, htpasswd, LDAP, Bearer/OAuth2 ([admin configuration](https://zotregistry.dev/v2.1.18/admin-guide/admin-configuration/)). Identity-based authorization (read/create/update/delete per path) is first-party ([admin configuration](https://zotregistry.dev/v2.1.18/admin-guide/admin-configuration/)). Anonymous policies are expressible in config ([config-anonymous-authz.json](https://github.com/project-zot/zot/blob/main/examples/config-anonymous-authz.json)). Unlike Distribution’s token mode, basic auth does not require a separate token issuer service for the common htpasswd path.

**Feature surface.** Minimal: Dist Spec push/pull/store. Full: sync, search/GraphQL, scrub, metrics, lint, UI, mgmt, imagetrust (cosign/notation), events, inline GC and dedupe ([architecture](https://zotregistry.dev/v2.1.18/general/architecture/), [concepts](https://zotregistry.dev/v2.1.18/general/concepts/)). Extensions are build-time and/or config-gated ([architecture](https://zotregistry.dev/v2.1.18/general/architecture/)).

**Operational fit.** Single container or binary; Podman examples are first-party; one JSON/YAML config; data under a configurable `rootDirectory` (default `/var/lib/registry` in published images) ([released images](https://zotregistry.dev/v2.1.18/general/releases/)). Strong Quadlet candidate, especially **zot-minimal**.

**Deal-breakers.** Using the **full** default image (UI + search + CVE) expands attack surface and background work — fine as optional, poor as the default for “just images.” Scale-out/cluster modes and Redis-backed features exist in examples but are unnecessary for a solo Host.

---

## Side-by-side (Tier A)

| Dimension | Distribution `registry:3` | zot-minimal | zot (full defaults) |
| --- | --- | --- | --- |
| Language | Go | Go | Go |
| CNCF | Sandbox (2021) | Sandbox (2022) | same |
| Wire API | OCI Dist Spec 1.0.1 (project claim) | OCI Dist Spec (conformance claimed; config cites 1.1.x) | same + extensions |
| On-disk layout | Distribution storage layout | OCI Image Layout only | same |
| Processes / deps | 1 container; filesystem | 1 container/binary; filesystem | 1 process but heavier extensions (Trivy DB if CVE on) |
| Official image | `registry:3` | `ghcr.io/project-zot/zot-minimal` | `ghcr.io/project-zot/zot` |
| Config surface | Optional YAML / `REGISTRY_*` | Small JSON/YAML | Larger JSON + extensions |
| Auth MVP | None, or htpasswd+TLS, or external token | None, or built-in htpasswd/LDAP/Bearer + policies | same |
| UI / scanning | No | No | Yes (default search/UI/CVE) |
| Podman docs | Implicit (OCI image) | Explicit `podman run` examples | Explicit |

---

## Screened and dismissed

### Harbor (CNCF Graduated) — too heavy

Harbor “extends the open source Docker Distribution by adding the functionalities usually required by users such as security, identity and management” ([README](https://github.com/goharbor/harbor/blob/main/README.md)). CNCF **Graduated** (accepted 2018, graduated 2020) ([CNCF Harbor](https://www.cncf.io/projects/harbor/)).

**Why not:** Official **minimum 4 GB RAM / 2 CPU / 40 GB disk**; recommended 8 GB / 4 CPU ([installation prerequisites](https://goharbor.io/docs/latest/install-config/installation-prereqs/)). Architecture is a **stack**: Nginx proxy, core, jobservice, PostgreSQL, Redis, registry, portal, optional Trivy/Notary, etc. ([architecture wiki](https://github.com/goharbor/harbor/wiki/Architecture-Overview-of-Harbor)). Compose template services include `proxy`, `core`, `portal`, `jobservice`, `registry`, `registryctl`, `postgresql`, `redis`, `log`, `trivy-adapter`, `exporter` ([v2.15.2 compose template](https://raw.githubusercontent.com/goharbor/harbor/v2.15.2/make/photon/prepare/templates/docker_compose/docker-compose.yml.jinja)). That is a control plane, not a lightweight Component.

### Sonatype Nexus Repository — too heavy

Multi-format repository manager. **Small** profile: **2 CPUs, 8 GB RAM**; container-based H2 deployments are **not supported** ([system requirements](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html)). JVM-centric; wrong weight class for a solo Host image registry Component.

### Project Quay / Red Hat Quay — multi-component platform

Supports Docker Registry Protocol v2 and OCI ([README](https://github.com/quay/quay/blob/master/README.md)). Local/dev topology already needs **Quay + PostgreSQL + Redis**, and optionally **Clair + Clair DB** ([getting started](https://github.com/quay/quay/blob/master/docs/getting-started.md)). Python application with workers and UI — not a minimal Dist Spec daemon. **Quay.io** managed service is out of scope as a Component.

### Spegel — mirror, not a push registry

“Stateless cluster local **OCI registry mirror**” for Kubernetes/containerd pull acceleration ([README](https://github.com/spegel-org/spegel/blob/main/README.md)). Deployed via Helm into a cluster; depends on containerd registry mirroring ([getting started](https://spegel.dev/docs/getting-started/)). Does not replace a place to **push** images for storage.

### Dragonfly — P2P acceleration

CNCF **Graduated** P2P data distribution / image acceleration ([CNCF Dragonfly](https://www.cncf.io/projects/dragonfly/), [README](https://github.com/dragonflyoss/dragonfly/blob/main/README.md)). Multi-component delivery mesh, not a small private registry.

### Uber Kraken — P2P registry distribution layer

“P2P-powered Docker registry” focused on scalability; agents on every host, tracker, origin, proxy, build-index ([README](https://github.com/uber/kraken/blob/master/README.md)). Built for large hybrid-cloud clusters; far from a single Quadlet.

### JFrog Artifactory — enterprise platform

Universal binary repository (Docker is one format among many). Self-managed installs are a full platform with DB and substantial ops surface ([JFrog installation docs](https://jfrog.com/help/r/jfrog-installation-setup-documentation/system-requirements)). Not a minimal OCI registry Component.

### Managed registries — wrong packaging

GitHub GHCR, GitLab.com Container Registry, Quay.io, cloud provider registries: ready-to-use push/pull endpoints, but **not** something Prefect runs as a Host Component. Distribution’s own docs point users who want “zero maintenance” at hosted registry services ([docs home — Alternatives](https://distribution.github.io/distribution/)).

### Clients / libraries — not servers

- **ORAS** — OCI registry **client** for artifacts ([oras-project/oras](https://github.com/oras-project/oras)).
- **google/go-containerregistry** — Go libraries/tooling to talk to registries, not a registry server.
- **containers/image** — image copy/transport library used by Podman et al., not a registry daemon.

### Other notes

- **`registry:2` vs `registry:3`:** current Distribution docs and quickstarts use **`registry:3`** ([docs home](https://distribution.github.io/distribution/), [deploy](https://distribution.github.io/distribution/about/deploying/)).
- **Joxit/docker-registry-ui:** UI in front of a registry; not a registry itself (listed as auxiliary UI in zot’s comparison references ([COMPARISON.md](https://github.com/project-zot/zot/blob/main/COMPARISON.md))).
- **ttl.sh-style ephemeral registries:** public ephemeral push services are not a self-hosted Prefect Component; not pursued further here.
- **zot `COMPARISON.md`:** useful for feature dimensions, but its embedded “last stable release” dates are outdated relative to current GitHub releases — do not use that file for maturity dates.

---

## Resource evidence policy (repeat)

- Harbor’s “4 GB minimum” and Nexus’s “8 GB small” are **vendor deployment floors**, not idle RSS of Distribution/zot.
- Image compressed size ≠ runtime memory.
- Prefer a Prefect Host experiment (cgroup memory/CPU for `registry:3` vs `zot-minimal` under idle + one push/pull) before ranking the two Tier A options on footprint alone.

---

## Implications for Prefect

A Component that wraps an existing registry looks **viable**: both Tier A options are single-container Dist Spec servers with filesystem storage that can bind-mount durable bytes on the Host Volume and expose Registry HTTP API V2 push/pull to Workloads or the operator over the Service Network / Edge — without adopting Harbor-scale compose stacks.

**Strongest fit for low footprint + minimal API + simplicity + Go:** **CNCF Distribution (`registry:3`)** as the simplest “already-existing solution” (one image, optional config, industry-standard reference). **`ghcr.io/project-zot/zot-minimal`** is the peer choice when Prefect prefers OCI Image Layout on disk, first-party Podman docs, and built-in auth/policy without an external token service — still Go, still CNCF, still one process. Prefer **zot-minimal** over full zot defaults so UI/CVE extensions do not become accidental standing cost on a small Host.
