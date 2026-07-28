# Cursor Agent sandbox and host isolation

**Researched:** 2026-07-28  
**Question:** What security boundary does Cursor's local Agent sandbox provide, and how does it compare with a non-root container using a bind-mounted, non-root-owned host directory?  
**Scope:** Cursor IDE and CLI sandboxing on macOS and Linux, compared primarily with Linux rootless Podman on this project's Ubuntu hosts.  
**Method:** Primary sources only: Cursor, Podman/Red Hat, Docker, Linux kernel/man-pages, and Apple documentation. Claims distinguish documented product behavior, kernel mechanisms, and configuration-dependent hardening; neither sandbox nor container is treated as a perfect security boundary.

---

## Verdict

1. Cursor's local sandbox is a useful least-authority layer for **supported terminal subprocesses**, not a guarantee that the whole Agent is confined. Direct first-party file tools, approved MCP tools, Browser/Fetch, and deliberately unsandboxed commands remain separate capabilities.
2. A hardened **rootless Podman container running a non-root container user** provides stronger isolation for hostile builds or tests through user, PID, mount, IPC, and network namespaces plus an explicit container filesystem. It still shares the host kernel.
3. A writable bind mount remains a direct write path to host data. Container disposal does not undo those writes, and rootless operation does not protect data intentionally exposed to the container.
4. “Non-root container” is ambiguous. A non-root process under a rootful engine is not equivalent to a rootless engine; combining rootless Podman with a non-root container UID adds both boundaries.

---

## 1. Sandboxing and automatic approval

### IDE

Run Modes govern shell, MCP, and Fetch approvals:

- **Auto-review:** allowlisted calls run immediately; shell commands run in the sandbox when possible; non-sandboxed calls go to a classifier. If blocked and still justified, Cursor can show an approval prompt.
- **Allowlist:** only explicitly allowed operations avoid prompting.
- **Run Everything:** every tool call runs automatically, with no sandbox and no classifier.

Thus Auto-review can be both automatic and sandboxed, but it does not promise zero prompts. Commands requiring full system access bypass the sandbox and can require approval. `permissions.json` steers Auto-review/allowlists; `sandbox.json` controls extra paths and network policy ([Run Modes](https://cursor.com/docs/agent/security/run-modes), [permissions](https://cursor.com/docs/reference/permissions), [sandbox configuration](https://cursor.com/docs/reference/sandbox)).

The sandbox is documented specifically around **terminal command execution**. Cursor separately documents that Agent can edit normal workspace files without approval. **Inference:** sandboxing a shell command does not place the direct file-edit tool inside that command sandbox; file tools follow their own workspace/config-file controls. MCP calls likewise have their own connection/tool approvals and allowlists rather than automatically executing inside the shell sandbox ([Agent security](https://cursor.com/docs/agent/security), [terminal sandbox](https://cursor.com/docs/agent/tools/terminal), [MCP approvals](https://cursor.com/docs/agent/security#mcp)).

### CLI

Interactive CLI asks before terminal execution by default. The unattended, write-enabled, shell-sandboxed shape is:

```bash
agent -p --force --sandbox enabled --model "<model-id>" "Your task"
```

Relevant flags:

- `-p` / `--print`: non-interactive output; retains write and shell tools.
- `--force`: allows direct changes/commands without confirmation unless explicitly denied.
- `--sandbox enabled`: enables the command-execution sandbox.
- `--trust`: skips workspace-trust prompting in headless mode.
- `--approve-mcps`: automatically approves MCP servers; this is separate from shell sandboxing.

Persistent alternatives are `agent sandbox enable`, `agent sandbox disable`, and interactive `/sandbox` ([CLI parameters](https://cursor.com/docs/cli/reference/parameters), [CLI overview](https://cursor.com/docs/cli/overview#sandbox-controls), [headless mode](https://cursor.com/docs/cli/headless)).

**Inference:** `--sandbox enabled` primarily constrains shell commands. CLI documentation simultaneously says print mode has write tools/full write access and separately defines sandbox mode as command execution. Do not treat the flag as a general confinement boundary for direct file tools or MCP servers. Restrict the workspace, credentials, MCP configuration, and host/container permissions independently.

---

## 2. Exact Cursor sandbox boundary

Cursor's Run Modes documentation says sandboxing is a layer on top of Run Modes for shell commands and controls where a supported terminal command runs. Its Terminal page likewise scopes the sandbox to terminal commands. Separately, Agent Security says reads/searches do not require approval, workspace edits can occur without approval, and MCP connections/tool calls have their own approval or allowlist path. Therefore:

- The sandbox constrains the sandboxed terminal subprocess tree, not all Agent capabilities.
- A direct file read/edit does not become a syscall made by that subprocess merely because sandboxing is enabled. Workspace edits save directly to disk; first-party external-file protection is an approval control, not documented OS containment.
- An MCP server executes according to where and how that server is deployed and what credentials/tools it has. Approving or allowlisting MCP is independent of terminal sandboxing.
- Fetch and browser/network tools have their own product policies. The terminal network allowlist is not a universal egress policy for all Agent tools.
- A command that needs full system access can run **outside** the sandbox after the applicable approval/review path. Run Everything disables sandbox and classifier entirely.

This boundary matters for prompt injection: malicious repository text may persuade the model to call any capability it has. The shell sandbox limits one class of call; it does not sanitize prompts or remove direct file, MCP, Browser, Fetch, or credential-bearing capabilities. Minimize those capabilities independently and retain human approval for high-impact operations ([Agent security](https://cursor.com/docs/agent/security), [Run Modes](https://cursor.com/docs/agent/security/run-modes), [MCP](https://cursor.com/docs/mcp)).

### Platform implementations

- **macOS:** Seatbelt via `sandbox-exec`; Cursor says the generated profile limits filesystem, network, and other process behavior for the full subprocess tree. Apple documents App Sandbox as its supported entitlement-based application sandbox, while Apple DTS states that custom `sandbox-exec`/SBPL profiles are deprecated and the profile language is not a supported third-party API. That does not show Cursor's profile is ineffective, but the public Apple contract is weaker than a stable documented SBPL specification ([Run Modes](https://cursor.com/docs/agent/security/run-modes#how-sandboxing-works-on-your-platform), [Apple App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [Apple DTS on custom sandboxes](https://developer.apple.com/forums/thread/661939)).
- **Linux:** Landlock restricts filesystem access and seccomp blocks unsafe syscalls. Cursor requires kernel 6.2+ with Landlock v3 and unprivileged user namespaces; otherwise it falls back to approval rather than silently claiming equivalent sandboxing. Remote/CLI environments may need Cursor's AppArmor package to permit sandbox creation. The sandbox maps the process to UID 0 inside a user namespace; that is namespace root, not host root. Cursor reports whether Landlock or its Bubblewrap fallback is active through `CURSOR_SANDBOX_LANDLOCK_STATUS` ([Run Modes](https://cursor.com/docs/agent/security/run-modes#linux), [Landlock](https://docs.kernel.org/userspace-api/landlock.html), [seccomp](https://docs.kernel.org/userspace-api/seccomp_filter.html), [user namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)).
- **Other operating systems:** current documentation describes macOS and Linux backends. This is an absence-of-documentation finding, not proof that no other backend exists.

The Linux kernel explicitly warns that seccomp filtering is **not a sandbox by itself**. It reduces syscall surface and must be combined with other controls. Landlock is a stackable restriction on ambient rights; namespaces are useful isolation building blocks but are not fine-grained access control. Cursor's combination is meaningful defense in depth, not an escape-proof guarantee ([seccomp](https://docs.kernel.org/userspace-api/seccomp_filter.html#what-it-isn-t), [Landlock](https://docs.kernel.org/userspace-api/landlock.html)).

### What `sandbox.json` does—and does not promise

- `type: "workspace_readwrite"` is the default and gives sandboxed commands read/write access in the workspace. `"workspace_readonly"` makes that workspace access read-only; `"insecure_none"` disables the sandbox.
- `additionalReadwritePaths` adds paths a sandboxed command can read and write, and only applies to `workspace_readwrite`. `additionalReadonlyPaths` adds read-only paths. Broad home-directory grants materially weaken isolation.
- Protected paths such as `.git/config`, `.git/hooks/**`, `.vscode/**`, `.cursorignore`, and sensitive Cursor/Claude JSON configuration are always **write-protected**. The reference does not say every protected path is unreadable. SSL-certificate paths and `~/.ssh` are explicitly always readable.
- `/tmp` and platform temporary directories are writable by default. `disableTmpWrite: true` removes that default grant. Shared build caches intentionally create persistence across sandboxed and unsandboxed commands.
- `networkPolicy.default` defaults to `"deny"` in `sandbox.json`, with domain/wildcard/CIDR rules and deny taking priority. Private, loopback, IPv6-private, and cloud-metadata addresses are blocked by default. The product's default UI mode is **sandbox.json + Defaults**, which also permits Cursor's built-in package/tool domains; “Allow All” overrides the file. Rules match hosts, not URL paths.
- User, repository, team-admin, and hardcoded policies merge. Path grants are unioned; restrictive booleans and deny rules accumulate; local configuration cannot weaken team/hardcoded protections.

Cursor does not publish a complete deny-by-default matrix for every host path or file descriptor. The defensible promise is the documented workspace, additional-path, protected-path, and network behavior—not “the command can read nothing else.” Inherited environment variables, already-open descriptors, platform services, and implementation defects are not exhaustively specified ([sandbox reference](https://cursor.com/docs/reference/sandbox), [Run Modes network access](https://cursor.com/docs/agent/security/run-modes#network-access)).

---

## 3. Container boundaries that must not be conflated

1. **Non-root process inside a rootful container engine.** `--user` or image `USER` removes ordinary in-container root authority, but the rootful engine/runtime starts from host-root privilege. Without user-namespace remapping, numeric IDs may correspond directly to IDs on a bind-mounted host filesystem. This is not “rootless.”
2. **Rootless container engine/user namespace.** Podman and the runtime execute as an ordinary host user. Container IDs map through that user's `/etc/subuid` and `/etc/subgid` ranges; even container UID 0 has no root privilege in the host's initial user namespace. This mitigates engine/runtime and container-root compromise, but does not erase the host user's access or protect writable mounts.
3. **Rootless engine plus a non-root container user.** This adds least privilege inside the container to the outer user-namespace boundary. A compromise must first escape the application UID before using namespace-root powers, and namespace root remains mapped to unprivileged host IDs. This is the preferred baseline.

Capabilities are namespace-scoped. UID 0 in a user namespace can hold powers over resources owned by that namespace without becoming host root. Conversely, a non-root process can still receive capabilities, so “non-root” and “no capabilities” are independent controls. `--cap-drop=all` and `--security-opt=no-new-privileges` should be explicit rather than inferred from `--user` ([Podman rootless mode](https://docs.podman.io/en/latest/markdown/podman.1.html#rootless-mode), [Podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html), [user namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html), [capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)).

### Bind mounts, ownership, and the host boundary

A bind mount deliberately makes a host path visible inside the container. `:ro` prevents writes through that mount; `:rw` makes host effects persistent and bypasses the disposability of the image/root filesystem. The mounted subtree is real host data, not a copy.

UID behavior is configuration-dependent:

- Podman does not change source ownership by default. In a user namespace, a container UID/GID can correspond to a different host UID/GID, so access follows the translated ID plus host DAC/ACL/LSM checks.
- `--userns=keep-id` maps the caller's UID/GID to the same values inside the container. This is convenient for a developer-owned checkout but intentionally lets the process exercise that user's permissions on the bind mount.
- The `:U` volume option recursively `chown`s the host source to host IDs corresponding to the container user. It mutates the host tree and can be slow.
- Current Podman documentation says bind-mount `idmap` is supported only in rootful mode because unprivileged users cannot create those idmapped filesystems. Verify deployed kernel and Podman behavior before prescribing it for rootless operation.
- On SELinux hosts, `:z`/`:Z` relabeling is an independent host-policy step. Disabling labels or using an incorrectly labelled mount changes confinement independently of rootless mode.

A directory being owned by a non-root user is not automatically safe. If the mapped container identity can write it, malicious code can alter source, hooks, generated artifacts, or configuration later executed on the host. Mount only the required subtree; use `:ro` unless writes are necessary; keep secrets and control sockets outside it; inspect resulting ownership and labels ([Podman volumes](https://docs.podman.io/en/latest/markdown/podman-run.1.html#volume-vsource-volume-host-dir-container-diroptions), [Docker user-namespace caveats](https://docs.docker.com/engine/security/userns-remap)).

---

## 4. Comparison

| Property | Cursor local shell sandbox | Non-root user in rootful container | Rootless Podman + non-root container user |
| --- | --- | --- | --- |
| Boundary covered | Supported terminal subprocess tree only | Container process tree; engine/runtime remains rootful | Container process tree plus unprivileged engine/runtime |
| Host filesystem visibility | Workspace and configured grants; complete read matrix is not documented | Image plus mounts, but rootful privilege/misconfiguration can expose more | Image plus configured mounts; host-user-accessible data remains reachable if mounted |
| Writable host checkout | Workspace writable by default | Writable bind mount changes host files according to host IDs/mapping | Same consequence; mapping, `keep-id`, and `:U` determine effective ownership |
| Direct Agent file/MCP tools | Outside shell sandbox | Outside unless Cursor itself runs in container | Outside unless entire Agent runtime and MCP servers are containerized |
| Process isolation | Full subprocess tree on macOS; Linux restrictions inherit through sandboxed children | OCI PID and other namespaces by default | PID/mount/IPC/network/user namespaces, subject to flags |
| Syscalls/capabilities | Linux seccomp plus user namespace; product-defined policy | OCI defaults, but rootful engine raises consequences | OCI seccomp plus user namespace; capabilities and no-new-privileges remain explicit |
| Network | Domain/CIDR terminal policy; default UI adds built-in allowlist | Normally outbound access through container network | Same; use `--network=none` or independent egress enforcement |
| Kernel/escape risk | Host kernel and OS sandbox implementation | Shared host kernel; escape can reach rootful control plane | Shared host kernel; user namespace reduces post-escape privilege but is not a VM |
| Sockets/devices | Accessible host endpoints can collapse limits | Mounted engine sockets/devices expand authority | Rootless Podman socket grants control as host user and must not be mounted |
| Credentials | Children inherit environment unless scrubbed; `~/.ssh` is documented readable | Only injected/mounted credentials, but process can read them | Same; rootless operation does not redact secrets |
| Persistence | Workspace, temp, extra paths, and caches persist as configured | Bind mounts/volumes persist; writable layer lasts until removal | `--rm` removes container, not bind-mounted changes or retained volumes |
| Resource limits | No documented sandbox CPU/memory/PID quota | cgroup limits are separate options | Limits remain separate and depend on rootless cgroup delegation |

---

## 5. Hardened rootless Podman baseline

For Ubuntu/rootless Podman, these are independent controls—not consequences of merely saying “container” or “non-root”:

1. Run Podman rootless under a dedicated, minimally privileged host account with subordinate UID/GID ranges.
2. Run the image as a numeric non-root UID/GID. Drop all capabilities unless specifically required and set `no-new-privileges`.
3. Mount only the required project subtree. Prefer read-only input plus a narrow writable output mount. Do not mount `$HOME`, SSH/GPG/cloud configuration, `/run`, `/var/run`, `/proc`, `/sys`, engine sockets, or system sockets.
4. Use a read-only root filesystem where feasible, explicit `tmpfs` mounts for necessary ephemeral paths, and disposable volumes.
5. Keep Podman's default seccomp profile or a tested narrower profile. Keep SELinux/AppArmor confinement active and correctly label only required mounts.
6. Use `--network=none` when possible. Rootless Podman does not itself provide Cursor-style domain allowlisting; required egress needs an external controlled proxy/firewall policy.
7. Pass no host devices and never use `--privileged`, host PID/network/user namespaces, or broad `/dev` access.
8. Inject minimum, short-lived credentials. A compromised process can read its own environment and every mounted secret.
9. Set cgroup memory, CPU, PID, and optionally I/O limits; verify cgroup v2 delegation for the rootless user.
10. Use a disposable lifecycle with pinned images and explicit artifacts. Disposal does not undo bind-mount writes.

Illustrative shape—not a copy-paste guarantee because UID mapping, labels, paths, image requirements, and limits must be tested:

```bash
podman run --rm \
  --user 10001:10001 \
  --cap-drop=all \
  --security-opt=no-new-privileges \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=512m \
  --network=none \
  --memory=2g --cpus=2 --pids-limit=512 \
  --volume "$PWD:/workspace:rw" \
  --workdir /workspace \
  "<pinned-image>"
```

If only analysis is required, change the project mount to `:ro`. Add host-appropriate SELinux labelling only when required. Allowlisted network access requires an external enforcement point, not merely the default Podman network ([Podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html), [Podman resource limits](https://docs.podman.io/en/stable/markdown/podman-create.1.html), [Linux seccomp](https://docs.kernel.org/userspace-api/seccomp_filter.html), [Linux LSM](https://docs.kernel.org/admin-guide/LSM/index.html)).

---

## Security promises versus best effort

- **Documented Cursor promise:** supported sandboxed terminal commands receive documented path/network restrictions and the platform backend; unsupported Linux hosts fall back to approval.
- **Best effort:** Auto-review classification, model interpretation of prompts, and absence of implementation vulnerabilities. Cursor explicitly says the classifier is not a security boundary.
- **Not guaranteed by Cursor sandbox:** confinement of direct file tools, MCP, Browser/Fetch, unsandboxed approved commands, the whole Cursor process, secrets supplied to tools, resource quotas, or immunity from OS/kernel escape.
- **Documented container mechanisms:** namespaces isolate listed kernel resources; user namespaces map IDs/capabilities; seccomp filters syscalls; cgroups constrain selected resources; LSMs add host policy.
- **Not automatic from a container:** rootless engine, non-root application UID, read-only rootfs, capability drops, no-new-privileges, active seccomp/LSM policy, network restrictions, safe mounts, secret minimization, cgroup limits, and disposal must each be configured and verified.
- **Not guaranteed by a hardened container:** protection of writable bind-mounted data, safety of mounted sockets/devices/secrets, immunity from shared-kernel/runtime vulnerabilities, or protection from prompt injection through Agent capabilities outside the container.

---

## Corrections and caveats

- “`--sandbox enabled` sandboxes the Agent” is too broad. It primarily constrains supported terminal command execution.
- “Cursor's sandbox blocks all host-file reads” is unsupported. Cursor documents path behavior and protected writes, keeps SSL-certificate paths and `~/.ssh` readable, and does not publish an exhaustive read matrix.
- “A non-root container is rootless” is false. Process UID and engine privilege are independent.
- “A rootless container protects a writable bind mount” is false. UID mapping, DAC/ACL, LSM labels, and mount mode determine what can change.
- “Rootless Podman automatically supplies all hardening” is false. Every control in the baseline must be configured and verified independently.

---

## Sources

- [Cursor Agent security](https://cursor.com/docs/agent/security)
- [Run Modes and sandboxing](https://cursor.com/docs/agent/security/run-modes)
- [Sandbox configuration](https://cursor.com/docs/reference/sandbox)
- [Cursor terminal tool](https://cursor.com/docs/agent/tools/terminal)
- [Permissions and Auto-review configuration](https://cursor.com/docs/reference/permissions)
- [Cursor MCP](https://cursor.com/docs/mcp)
- [CLI overview](https://cursor.com/docs/cli/overview)
- [CLI headless mode](https://cursor.com/docs/cli/headless)
- [CLI parameters](https://cursor.com/docs/cli/reference/parameters)
- [Podman documentation and rootless mode](https://docs.podman.io/en/latest/markdown/podman.1.html)
- [Podman run](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
- [Podman resource limits](https://docs.podman.io/en/stable/markdown/podman-create.1.html)
- [Red Hat rootless containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_starting-with-containers_building-running-and-managing-containers)
- [Docker rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Docker user-namespace remapping](https://docs.docker.com/engine/security/userns-remap)
- [Linux namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [Linux user namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Linux capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [Linux seccomp](https://docs.kernel.org/userspace-api/seccomp_filter.html)
- [Linux Landlock](https://docs.kernel.org/userspace-api/landlock.html)
- [Linux Security Modules](https://docs.kernel.org/admin-guide/LSM/index.html)
- [Apple App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [Apple DTS on custom `sandbox-exec` profiles](https://developer.apple.com/forums/thread/661939)
