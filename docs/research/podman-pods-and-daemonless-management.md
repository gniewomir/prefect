# Podman pods and daemonless management

**Researched:** 2026-07-30  
**Question:** How do Podman pods work, and how does Podman achieve daemonless management of containers and pods?  
**Scope:** Architecture and operator-relevant defaults for Podman pods (namespaces, infra/pause, networking, lifecycle, Quadlets, rootful vs rootless) and the daemonless process model (CLI → conmon → OCI runtime; optional REST API; on-disk state). Not a Prefect-specific design doc.  
**Method:** Primary sources only — Podman man pages on docs.podman.io, containers/podman README and tutorials, containers.conf / storage.conf, containers/conmon README and man page, and libpod source where needed to pin database paths. Secondary blogs/issues used only as leads and verified against primary docs/source.

---

## Verdict

A **Podman pod** is a group of containers that share selected kernel namespaces, held open by a lightweight **infra (pause) container**. By default the shared set matches Kubernetes (`ipc`, `net`, `uts`); PID and cgroup namespaces are optional; **mount is not among the documented `--share` namespaces**. Each container still has its own root filesystem / mount namespace and its own **conmon**.

Podman is **daemonless** for normal CLI use: there is no always-on manager like `dockerd`. Each `podman` invocation opens on-disk state, starts (or talks to) containers via **conmon** + an OCI runtime (**crun**/**runc**), then exits. Containers keep running because **conmon** (and the container process) survive. Optional **`podman system service`** and **systemd/Quadlet** are add-ons for API access and long-lived supervision — not prerequisites for `podman run`.

---

## A. How Podman pods work

### What a pod is

- Podman manages **pods, containers, images, and volumes** via **libpod** ([Podman overview](https://docs.podman.io/en/latest/), [README](https://github.com/containers/podman/blob/main/README.md)).
- A pod is an empty unit prepared to hold containers: create with `podman pod create`, add with `podman create --pod …` / `podman run --pod …`, start with `podman pod start` ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [podman-pod(1)](https://docs.podman.io/en/latest/markdown/podman-pod.1.html)).
- README scope: “Support for pods, groups of containers that share resources and are managed together” and “No manager daemon” ([README](https://github.com/containers/podman/blob/main/README.md)).

### Relationship to Kubernetes pods

- Podman’s default shared namespaces are documented as matching the **Kubernetes default**: `ipc`, `net`, `uts` ([podman-pod-create(1) `--share`](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- `podman kube play` recreates Kubernetes Pods (and related kinds) as local Podman pods/containers; supported kinds include Pod, Deployment, DaemonSet, PersistentVolumeClaim, ConfigMap, Secret, etc. ([podman-kube-play(1)](https://docs.podman.io/en/latest/markdown/podman-kube-play.1.html)).
- Kube play and Quadlets default pod **`--exit-policy=stop`** (stop infra when the last container exits); CLI `podman pod create` defaults to **`continue`** ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [podman-systemd.unit(5)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)).
- This is **local pod semantics inspired by Kubernetes**, not a claim that Podman is a Kubernetes node agent. CRI is explicitly out of Podman’s scope; **CRI-O** covers that ([README — Out of scope](https://github.com/containers/podman/blob/main/README.md)).

### Shared namespaces (defaults vs optional)

Documented `--share` namespaces: **`cgroup`, `ipc`, `net`, `pid`, `uts`** ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).

| Namespace | Default shared? | Notes |
| --- | --- | --- |
| **net** | Yes | Shared network stack: one interface/IP/port space per pod ([podman-run(1) `--publish` note](https://docs.podman.io/en/latest/markdown/podman-run.1.html), [basic networking tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)) |
| **ipc** | Yes | Shared IPC (and `/dev/shm` sizing via pod `--shm-size`) |
| **uts** | Yes | Shared hostname; `--hostname` on the pod applies to all containers |
| **pid** | No | Private PID namespace for the pod by default; sharing requires `--share` including `pid`. `--pid` on the pod “Requires the PID namespace to be shared via `--share`” ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)) |
| **cgroup** | No | Optional via `--share=cgroup`. Separate from **`--share-parent`** (default **true**): containers use the **pod as cgroup parent** without sharing the cgroup *namespace* ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)) |
| **mount** | Not in `--share` list | Not a documented `--share` choice. Each container keeps its own rootfs/mounts; pod-level `--volume` mounts are applied to containers joining the pod, but that is volume configuration, not a shared mount namespace |

If `--share` is empty/`""`, **no namespaces are shared** and the infra container is **not** created unless `--infra=true` ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)). Prefix `+` appends to the default list; otherwise the list replaces defaults.

`podman pod inspect` exposes `SharedNamespaces` (examples show `uts`, `ipc`, `net`) ([podman-pod-inspect(1)](https://docs.podman.io/en/latest/markdown/podman-pod-inspect.1.html)).

### Infra / pause container

- **Role:** “lightweight container used to coordinate the shared kernel namespace of a pod” ([podman-pod-create(1) `--infra`](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)). containers.conf: start a `/pause` process “to **hold open the namespaces** associated with the pod… reserving the pod’s resources for the lifetime of the pod” ([containers.conf(5) `infra_command` / `infra_image`](https://github.com/containers/container-libs/blob/main/common/docs/containers.conf.5.md)).
- **Default:** `--infra=true`; `--infra-command` default **`/pause`** ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- **Image:** Unless `--infra-image` is set, Podman uses a **custom local image** (no pull). containers.conf: by default engines “run a built-in container using the pause executable”; set `infra_image` to override ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [containers.conf(5)](https://github.com/containers/container-libs/blob/main/common/docs/containers.conf.5.md)).
- **Lifecycle:** Started first when a container is run in a pod that has an infra container ([podman-run(1) `--pod`](https://docs.podman.io/en/latest/markdown/podman-run.1.html)). For systemd-generated units, “An infra container runs across the **entire lifespan** of a pod” and is required for systemd to manage the pod’s main unit ([podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)).
- **Exit policy interaction:**
  - `continue` (CLI default): pod keeps running by keeping infra alive when the last user container exits.
  - `stop` (kube play / Quadlet default): pod **including infra** stops when the last container exits ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- **What if infra dies while app containers remain?** Primary man pages do **not** spell out a dedicated failure matrix. They do state that infra **holds/coordinates** shared namespaces for the pod’s lifetime. Operationally, Podman locates shared namespace paths via the infra container; if infra is gone while state still expects it, later start/join operations can fail (see also exit-policy / ordered stop behavior in libpod). Treat infra as **must stay up for the pod’s intended lifespan**; manage the pod as a unit (`podman pod stop` / systemd), not by killing infra alone.

### Networking model

- With shared **net** (default): all containers in the pod share **one network namespace** — same IP, MAC, and port space. One binder owns a port; another cannot bind the same port in the pod. Containers talk over **localhost** ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html), [basic networking tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)).
- **Publish ports on the pod**, not on individual pod members: “You must not publish ports of containers in the pod individually, but only by the pod itself”; publish cannot be modified after pod create ([podman-pod-create(1) `--publish`](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- DNS / hosts: `/etc/hosts` and resolv.conf options on the pod are **shared** across containers in the pod ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- **Rootful default network mode:** bridge (netavark). **Rootless default:** pasta. Documented on pod create `--network` and in the networking tutorial ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [basic networking](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)).
- Rootless pasta: containers are isolated from each other by default **unless** placed in a pod (shared net ns) or using host port mappings ([basic networking](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)).

### Creating and managing pods

| Mechanism | Role |
| --- | --- |
| `podman pod create` | Create empty pod; print ID ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)) |
| `podman run --pod NAME` / `podman create --pod` | Join existing pod; `--pod new:NAME` auto-creates ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)) |
| `podman pod start/stop/restart/rm/ps/inspect/…` | Pod-level lifecycle and inspection ([podman-pod(1)](https://docs.podman.io/en/latest/markdown/podman-pod.1.html)) |
| Quadlet **`.pod`** | Declarative `[Pod]` unit → generated systemd service (`ExecStartPre=podman pod create …`); containers link with `Pod=` ([podman-systemd.unit(5)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html), [podman-quadlet(1)](https://docs.podman.io/en/latest/markdown/podman-quadlet.1.html)) |
| `podman generate systemd` | **Deprecated** in favor of Quadlets; still present for urgent fixes only ([podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html), [podman(1)](https://docs.podman.io/en/latest/markdown/podman.1.html)) |

Quadlet pod defaults: pod name `systemd-$name`; `ExitPolicy=stop`; generated service `Type=forking` for `.pod` files; use `Restart=always` in `[Service]` if you want restart when containers exit cleanly under `ExitPolicy=stop` ([podman-systemd.unit(5)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)).

### Joining a pod — constraints

Documented constraints when using `--pod`:

- **Ports:** publish via the pod only ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)).
- **`--uidmap` / `--gidmap`:** cannot be set on the container when joining a pod ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)).
- **`--userns`:** ignored if `--pod` is set; pod userns is used ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)).
- **Network attributes on a member container:** libpod error `ErrNetworkOnPodContainer` — “network cannot be configured when it is shared with a pod” / infra holds network info ([libpod/define/errors.go](https://github.com/containers/podman/blob/main/libpod/define/errors.go)). `podman run --network` with `--pod`: “If used together with `--pod`, the container joins the pod’s network namespace” ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)).
- **Hostname:** with shared UTS (default), the pod’s hostname is used ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)).
- Infra starts first when present ([podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)).

### Resource management / cgroups

- Pod-level limits (`--cpus`, `--memory`, …) set limits on the **pod’s cgroup parent** for containers joining the pod. A joining container may set a **smaller** limit; containers with their own cgroup (e.g. `--cgroupns=host`) do **not** get pod-level resources ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- `--share-parent` default **true**: containers use the pod as cgroup parent ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- Quadlet: default container `CgroupsMode=split`; for pod resource limits, docs recommend `no-conmon` or `enabled` when `Pod=` is set ([podman-systemd.unit(5)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)).
- Many resource flags are **not supported on cgroups V1 rootless** ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [rootless.md](https://github.com/containers/podman/blob/main/rootless.md)).

### Rootful vs rootless (pod-relevant)

| Concern | Rootful | Rootless |
| --- | --- | --- |
| Default net | bridge / netavark | pasta ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html), [basic networking](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)) |
| Low ports | Can bind &lt;1024 | Typically not without sysctl / capability ([rootless.md](https://github.com/containers/podman/blob/main/rootless.md)) |
| Pod localhost | Works via shared net ns | Same — primary reason to use pods for multi-container apps under pasta ([basic networking](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)) |
| User NS | Optional | Default mapping model; pod `--userns` applies to all containers in the pod ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)) |
| Devices | Can create nodes | Bind-mount from host; SELinux/`container_use_devices` notes apply ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)) |

**Separate rootless pause:** Rootless Podman also keeps a **user-namespace pause process** (not the pod infra) so unprivileged namespaces stay alive across container starts; `podman system migrate` stops it when remapping subuid/subgid ([podman-system-migrate(1)](https://docs.podman.io/en/latest/markdown/podman-system-migrate.1.html)). Do not confuse with the **per-pod** infra container.

### Lifecycle: pod vs containers

- **`podman pod start`:** starts containers in the pod; “The pod must have a container attached to be started” ([podman-pod-start(1)](https://docs.podman.io/en/latest/markdown/podman-pod-start.1.html)).
- **`podman pod stop`:** stops containers in the pod ([podman-pod-stop(1)](https://docs.podman.io/en/latest/markdown/podman-pod-stop.1.html)).
- **`podman pod restart`:** stop+start running containers; start stopped ones ([podman-pod-restart(1)](https://docs.podman.io/en/latest/markdown/podman-pod-restart.1.html)).
- **`podman pod rm`:** removes stopped pods and their containers; `-f` stops first ([podman-pod-rm(1)](https://docs.podman.io/en/latest/markdown/podman-pod-rm.1.html)).
- **Exit policy** governs whether infra (and thus the pod) remains after the last user container exits ([podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- With systemd-generated pod units: manage via the **pod** unit, not individual container units alone ([podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)).

### Inspect / ps

- **`podman pod ps`:** pod ID, name, created, container count, **infra ID**, status (`Created` / `Running` / `Stopped` / `Exited` / `Dead`, plus filters like `degraded`) ([podman-pod-ps(1)](https://docs.podman.io/en/latest/markdown/podman-pod-ps.1.html)).
- **`podman pod inspect`:** config/state, `SharedNamespaces`, `InfraContainerID`, `ExitPolicy`, resource fields, member containers ([podman-pod-inspect(1)](https://docs.podman.io/en/latest/markdown/podman-pod-inspect.1.html)).

---

## B. Daemonless management

### What “daemonless” means

- Podman is described as a **“simple daemonless tool”** / “daemonless, open source… tool” ([podman(1)](https://docs.podman.io/en/latest/markdown/podman.1.html), [docs index](https://docs.podman.io/en/latest/)).
- README: “**No manager daemon**, for improved security and lower resource utilization at idle” ([README](https://github.com/containers/podman/blob/main/README.md)).
- Contrast with Docker’s typical model: a long-lived **dockerd** owns container lifecycle and holds runtime state. Podman has **no equivalent always-on engine** for ordinary CLI use; each command is a short-lived process that talks to the OCI runtime through **conmon** and persists state on disk.

### Process model

Typical path for `podman run -d`:

1. **`podman` CLI** (libpod) loads config + on-disk state.
2. Prepares OCI bundle; launches **conmon**.
3. **conmon** double-forks / daemonizes, then launches the **OCI runtime** (`crun`/`runc`) as its child ([conmon README](https://github.com/containers/conmon/blob/main/README.md)).
4. Runtime creates the container process per the [OCI runtime-spec](https://github.com/opencontainers/runtime-spec).
5. **`podman` exits**; **conmon + container** remain.

Podman documents that conmon runs in a **separate process** from Podman; `--conmon-pidfile` exists specifically so systemd can track the real supervisor ([podman-create(1) / create docs via run](https://docs.podman.io/en/latest/markdown/podman-create.1.html) — same option family as run).

### Role of conmon

From [conmon README](https://github.com/containers/conmon/blob/main/README.md) and [conmon(8)](https://github.com/containers/conmon/blob/main/docs/conmon.8.md):

- Monitor between a container manager (Podman/CRI-O) and an OCI runtime for **a single container**.
- Double-forks so the manager can exit while still watching the container.
- While running: attach socket / stdio forwarding; log to file or journal.
- On death: records exit time/code.
- Described as “the **smallest daemon a container can have**.”

So: after CLI exit, **conmon owns monitoring** of that container — not a central Podman daemon.

### Why `podman run -d` keeps running

Detached mode does not require a Podman daemon. The container process is a normal Linux process tree rooted under the OCI runtime/conmon. Podman’s next CLI invocation rediscovers the container via **storage + libpod DB**, not via an in-memory daemon.

### systemd integration (recommended long-lived management)

- Preferred declarative path: **Quadlets** — `.container`, `.pod`, `.network`, `.volume`, … under containers/systemd paths; a generator emits native systemd units ([podman(1)](https://docs.podman.io/en/latest/markdown/podman.1.html), [podman-systemd.unit(5)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html), [podman-quadlet(1)](https://docs.podman.io/en/latest/markdown/podman-quadlet.1.html)).
- `podman generate systemd` is **deprecated**; use Quadlets ([podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)).
- Generated units historically used `Type=forking` + **conmon PIDFile** so systemd supervises conmon, not the short-lived `podman` process ([podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)).
- **Linger:** for user systemd, enable lingering so the user instance survives logout (`loginctl enable-linger`) — documented for API socket and generated user units ([podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html), [podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)).
- When running under systemd, prefer systemd’s `Restart=` over container `--restart` ([podman-pod-create(1) `--restart`](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).

### Optional REST API (`podman system service`)

- Starts a listening API (Docker-compatible + Libpod native). Available on Linux; usually run under **systemd socket activation** ([podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)).
- With socket activation: service starts on connection, exits after idle timeout (default **5s**, configurable); **no continuous daemon** when idle ([podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)).
- Default sockets: rootful `unix:///run/podman/podman.sock`; rootless `unix://$XDG_RUNTIME_DIR/podman/podman.sock` ([podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)).
- **Does not make Podman require a daemon for normal CLI use.** It is for remote clients, Docker API tools, Compose-style workflows, etc. Security model: Unix socket permissions; TLS strongly recommended if TCP is used ([podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)).

### Rootless specifics tied to the management model

- No setuid manager daemon; user namespaces map container root to the calling user ([README — Rootless](https://github.com/containers/podman/blob/main/README.md)).
- Networking without creating host interfaces: **pasta** (default as of Podman 5.0 notes in rootless.md); historically **slirp4netns** ([README](https://github.com/containers/podman/blob/main/README.md), [rootless.md](https://github.com/containers/podman/blob/main/rootless.md), [podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)).
- User systemd + **linger** for services that must outlive login ([podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)).
- Rootless **pause process** for user namespaces (distinct from pod infra) ([podman-system-migrate(1)](https://docs.podman.io/en/latest/markdown/podman-system-migrate.1.html)).

### How pods fit the daemonless model

- A pod is **not** a long-lived Podman daemon. It is metadata + an **infra container** (itself supervised by **its own conmon**) plus member containers (each with **its own conmon**).
- Pod start/stop are CLI (or systemd unit) operations that start/stop those containers.
- Shared namespaces live in the kernel, held by the infra (and any joined processes), not by a Podman daemon.

### Storage and state (source of truth on disk)

No central daemon holds authoritative in-memory state. Persistence is split:

| Layer | What | Where (defaults) |
| --- | --- | --- |
| **containers/storage** | Images, container writable layers | `graphroot` default **`/var/lib/containers/storage`**; rootless **`$XDG_DATA_HOME/containers/storage`** or **`$HOME/.local/share/containers/storage`**. Transient: `runroot` default **`/run/containers/storage`** ([containers-storage.conf(5)](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)) |
| **libpod DB** | Containers, pods, volumes metadata | `static_dir` default **`/var/lib/containers/storage/libpod`** (“persistent libpod files (database, etc)”) ([containers.conf(5)](https://github.com/containers/container-libs/blob/main/common/docs/containers.conf.5.md)). SQLite file name **`db.sql`** under that base (libpod `sqliteDbFilename`) ([sqlite_state.go](https://github.com/containers/podman/blob/main/libpod/sqlite_state.go) / [sqlite_state_internal.go](https://github.com/containers/podman/blob/main/libpod/sqlite_state_internal.go)) |
| **tmp** | Per-boot runtime files | `tmp_dir` default **`/run/libpod`** (tmpfs) ([containers.conf(5)](https://github.com/containers/container-libs/blob/main/common/docs/containers.conf.5.md)) |
| **conmon logs / pidfiles** | Per-container | Under container storage userdata (as used by systemd PIDFile examples in [podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)) |

**Backend history (version-sensitive):** BoltDB was the legacy libpod backend; **support removed in Podman 6.0**. Migrate with `podman system migrate --migrate-db` (or reboot-triggered migration). Stop other Podman processes / Quadlets / `system service` before migrating ([podman-system-migrate(1)](https://docs.podman.io/en/latest/markdown/podman-system-migrate.1.html), [libpod/runtime.go](https://github.com/containers/podman/blob/main/libpod/runtime.go)).

Each `podman` invocation opens this on-disk state (with locking); that is how daemonless management remains consistent across CLI calls.

---

## Gaps / unclear in primary sources

- Exact failure semantics when the **infra container is killed** while member containers still run are not fully specified in man pages (only that infra holds namespaces for the pod lifetime).
- **Mount-namespace sharing** appears in libpod’s internal `UsePodMount` field but is **not** listed in `--share` in current podman-pod-create docs — treat mount as **not user-shareable via `--share`** unless future docs change.
- End-to-end “architecture” diagrams are thin on docs.podman.io; the process model is assembled from conmon’s README + Podman man pages + README scope bullets.

---

## Sources

- [What is Podman? (docs.podman.io)](https://docs.podman.io/en/latest/)
- [podman(1)](https://docs.podman.io/en/latest/markdown/podman.1.html)
- [podman-pod(1)](https://docs.podman.io/en/latest/markdown/podman-pod.1.html)
- [podman-pod-create(1)](https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html)
- [podman-pod-start(1)](https://docs.podman.io/en/latest/markdown/podman-pod-start.1.html)
- [podman-pod-stop(1)](https://docs.podman.io/en/latest/markdown/podman-pod-stop.1.html)
- [podman-pod-restart(1)](https://docs.podman.io/en/latest/markdown/podman-pod-restart.1.html)
- [podman-pod-rm(1)](https://docs.podman.io/en/latest/markdown/podman-pod-rm.1.html)
- [podman-pod-ps(1)](https://docs.podman.io/en/latest/markdown/podman-pod-ps.1.html)
- [podman-pod-inspect(1)](https://docs.podman.io/en/latest/markdown/podman-pod-inspect.1.html)
- [podman-run(1)](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
- [podman-create(1)](https://docs.podman.io/en/latest/markdown/podman-create.1.html)
- [podman-systemd.unit(5) (Quadlet)](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [podman-quadlet(1)](https://docs.podman.io/en/latest/markdown/podman-quadlet.1.html)
- [podman-generate-systemd(1)](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)
- [podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)
- [podman-system-migrate(1)](https://docs.podman.io/en/latest/markdown/podman-system-migrate.1.html)
- [podman-kube-play(1)](https://docs.podman.io/en/latest/markdown/podman-kube-play.1.html)
- [containers/podman README](https://github.com/containers/podman/blob/main/README.md)
- [Basic Networking Guide for Podman](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md)
- [Rootless shortcomings (rootless.md)](https://github.com/containers/podman/blob/main/rootless.md)
- [containers.conf(5)](https://github.com/containers/container-libs/blob/main/common/docs/containers.conf.5.md)
- [containers-storage.conf(5)](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)
- [conmon README](https://github.com/containers/conmon/blob/main/README.md)
- [conmon(8)](https://github.com/containers/conmon/blob/main/docs/conmon.8.md)
- [libpod/define/errors.go](https://github.com/containers/podman/blob/main/libpod/define/errors.go) (`ErrNetworkOnPodContainer`)
- [libpod/runtime.go](https://github.com/containers/podman/blob/main/libpod/runtime.go) (SQLite / BoltDB backend selection)
- [libpod/sqlite_state.go](https://github.com/containers/podman/blob/main/libpod/sqlite_state.go) / [sqlite_state_internal.go](https://github.com/containers/podman/blob/main/libpod/sqlite_state_internal.go) (`db.sql` path)
- [OCI runtime-spec](https://github.com/opencontainers/runtime-spec) (runtime interface Podman/conmon invoke)
