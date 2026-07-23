# Mandatory Host Volume on public Hosts

Public Hosts get a mandatory **Host Volume**: a Stack-owned 1 GiB block volume attached at Host create (`volume_ids`), assigned to Cloud Project `Prefect`, formatted `ext4` on first volume create only. It survives Host rebuilds; **Destroy** still removes it with the rest of the Stack. Initial Host Provisioning mounts it at `/var/lib/prefect` (fstab via `/dev/disk/by-id/…`, `defaults,nofail,discard,noatime`); the mount root stays root-owned. No Edge/Workload layout in this drop — consumers get subdirs later. Acceptance Tests assert State (size, attachment, Cloud Project URN) and a live mounted filesystem at `/var/lib/prefect`.

**One Host Volume over per-Workload volumes:** durable bytes are a Prefect carrier concern (parallel to Reserved IP for address). Split volumes later only if a Workload needs a separate lifecycle or isolation.

**Survive Host recreate, not Destroy:** matches how Destroy is used to iterate the Stack; durable data that must outlive Destroy waits until that need is real (e.g. non-reissuable DB state).

**`volume_ids` at Host create over post-create attachment:** the block device must be present for Initial Host Provisioning. Provider auto-mount under `/mnt/<volume-name>` happens only on first volume create and is not the Prefect contract — fstab to `/var/lib/prefect` is, including after Host recreate when the provider will not auto-mount again.

**Mount + fstab in Initial Host Provisioning over resource-only or deploy-time mount:** a mandatory Host Volume that nobody mounts is incomplete; the Host stays a carrier (no Quadlets here — ADR-0004).

**1 GiB, grow later:** smallest provider size; expand when a Workload needs bulk disk. Root-owned mount root until a consumer needs a chown’d subdirectory.
